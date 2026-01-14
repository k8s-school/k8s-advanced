#!/bin/bash

set -euxo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global variables
CONTROL_PLANE_CONTAINER=""
ORIGINAL_MANIFEST_BACKUP="$DIR/kube-apiserver.yaml.backup"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check Python YAML availability
check_python_yaml() {
    if ! python3 -c "import yaml" 2>/dev/null; then
        log_error "Python yaml module is not available. Please install it:"
        log_error "  sudo apt-get install python3-yaml  # or"
        log_error "  pip3 install pyyaml"
        exit 1
    fi
    log_success "Python YAML module available"
}

# Function to detect control plane container
detect_control_plane() {
    log_info "Detecting control plane container..."

    # Verify kubectl is working
    if ! kubectl get nodes >/dev/null 2>&1; then
        log_error "kubectl is not configured or cluster is not accessible"
        exit 1
    fi

    # Find the control plane container matching the current kubectl context
    local current_context=$(kubectl config current-context)
    local cluster_name=$(echo "$current_context" | sed 's/^kind-//')
    CONTROL_PLANE_CONTAINER="${cluster_name}-control-plane"

    # Verify the container exists
    if ! docker ps --filter "name=${CONTROL_PLANE_CONTAINER}" --format "{{.Names}}" | grep -q "${CONTROL_PLANE_CONTAINER}"; then
        log_error "Control plane container '${CONTROL_PLANE_CONTAINER}' not found for context '${current_context}'"
        log_error "Available control-plane containers:"
        docker ps --filter "name=control-plane" --format "{{.Names}}"
        exit 1
    fi

    log_success "Using control plane container: $CONTROL_PLANE_CONTAINER"
}

# Function to backup API server manifest
backup_api_server_manifest() {
    log_info "Backing up API server manifest..."

    # Backup locally
    docker cp "$CONTROL_PLANE_CONTAINER:/etc/kubernetes/manifests/kube-apiserver.yaml" "$ORIGINAL_MANIFEST_BACKUP"
    log_success "Backed up API server manifest to $ORIGINAL_MANIFEST_BACKUP"

    # Backup inside container
    docker exec "$CONTROL_PLANE_CONTAINER" cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak
    log_success "Backed up API server manifest inside container to /tmp/kube-apiserver.yaml.bak"
}

# Function to create audit policy
create_audit_policy() {
    log_info "Creating audit policy..."

    docker exec "$CONTROL_PLANE_CONTAINER" bash -c 'cat > /etc/kubernetes/audit-policy.yaml <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets"]
- level: RequestResponse
  resources:
  - group: ""
    resources: ["pods"]
EOF'

    log_success "Created audit policy at /etc/kubernetes/audit-policy.yaml"
}

# Function to modify API server manifest using Python
modify_api_server_manifest() {
    log_info "Modifying API server manifest using Python..."

    # Check Python YAML availability
    check_python_yaml

    # Create logs directory on control plane
    docker exec "$CONTROL_PLANE_CONTAINER" mkdir -p /var/log/kubernetes

    # Use Python to modify the YAML
    python3 << EOF
import yaml
import sys

try:
    # Read the backup file
    with open("${ORIGINAL_MANIFEST_BACKUP}", 'r') as f:
        data = yaml.safe_load(f)

    # Add audit command flags
    container = data['spec']['containers'][0]
    audit_flags = [
        '--audit-policy-file=/etc/kubernetes/audit-policy.yaml',
        '--audit-log-path=/var/log/kubernetes/audit.log',
        '--audit-log-maxsize=10'
    ]

    # Only add flags that aren't already present
    for flag in audit_flags:
        flag_name = flag.split('=')[0]
        if not any(cmd.startswith(flag_name) for cmd in container['command']):
            container['command'].append(flag)

    # Add audit volume mounts
    audit_mounts = [
        {'mountPath': '/etc/kubernetes/audit-policy.yaml', 'name': 'audit-policy', 'readOnly': True},
        {'mountPath': '/var/log/kubernetes', 'name': 'audit-logs'}
    ]

    for mount in audit_mounts:
        if not any(vm.get('name') == mount['name'] for vm in container.get('volumeMounts', [])):
            container.setdefault('volumeMounts', []).append(mount)

    # Add audit volumes
    audit_volumes = [
        {'hostPath': {'path': '/etc/kubernetes/audit-policy.yaml', 'type': 'File'}, 'name': 'audit-policy'},
        {'hostPath': {'path': '/var/log/kubernetes', 'type': 'DirectoryOrCreate'}, 'name': 'audit-logs'}
    ]

    for volume in audit_volumes:
        if not any(v.get('name') == volume['name'] for v in data['spec'].get('volumes', [])):
            data['spec'].setdefault('volumes', []).append(volume)

    # Clean up runtime metadata to make it suitable for static manifest
    runtime_fields = ['creationTimestamp', 'resourceVersion', 'uid', 'generation', 'ownerReferences']
    for field in runtime_fields:
        data['metadata'].pop(field, None)

    # Remove status section if it exists
    data.pop('status', None)

    # Write the modified file with proper YAML formatting
    with open('/tmp/kube-apiserver-work.yaml', 'w') as f:
        yaml.dump(data, f, default_flow_style=False, width=1000, indent=2, sort_keys=False)

    print("✓ Python YAML modification completed successfully")

except Exception as e:
    print(f"✗ Error modifying YAML: {e}")
    sys.exit(1)
EOF

    # Verify the result
    echo "=== Verifying generated manifest ==="
    echo "Audit flags: $(grep -c "audit-policy-file" /tmp/kube-apiserver-work.yaml)"
    echo "Audit mounts: $(grep -c "audit-policy" /tmp/kube-apiserver-work.yaml)"

    # Validate YAML syntax
    if python3 -c "import yaml; yaml.safe_load(open('/tmp/kube-apiserver-work.yaml'))" 2>/dev/null; then
        echo "✓ Generated manifest is valid YAML"

        # Copy the modified manifest to the control plane
        docker cp /tmp/kube-apiserver-work.yaml "$CONTROL_PLANE_CONTAINER:/etc/kubernetes/manifests/kube-apiserver.yaml"
        echo "Applied modified manifest"

        echo "Restart kubelet to apply the change quickly"
        docker exec -- "$CONTROL_PLANE_CONTAINER" systemctl restart kubelet
    else
        echo "✗ Generated manifest has YAML errors"
        log_error "YAML validation failed"
        exit 1
    fi

    log_success "Modified API server manifest to enable audit logging"
}

# Function to wait for API server restart
wait_for_api_server() {
    log_info "Waiting for API server to restart..."

    # Wait for the API server pod to be ready
    while ! kubectl get pods >/dev/null 2>&1; do
        echo "Waiting for API server to be ready..."
        sleep 10
    done

    log_success "API server is ready"
}

# Function to test audit logs
test_audit_logs() {
    log_info "Testing audit logs functionality..."

    # Create test resources
    log_info "Creating test secret..."
    kubectl create secret generic test-audit-secret --from-literal=key=value

    log_info "Creating test pod..."
    kubectl run test-audit-pod --image=nginx --restart=Never

    # Wait a bit for logs to be written
    sleep 3

    # Check for audit logs
    log_info "Checking audit logs..."

    local secret_logs
    local pod_logs

    secret_logs=$(docker exec "$CONTROL_PLANE_CONTAINER" bash -c 'grep -c "\"secrets\"" /var/log/kubernetes/audit.log 2>/dev/null' || echo "0")
    pod_logs=$(docker exec "$CONTROL_PLANE_CONTAINER" bash -c 'grep -c "\"pods\"" /var/log/kubernetes/audit.log 2>/dev/null' || echo "0")

    # Ensure they are integers
    secret_logs=${secret_logs:-0}
    pod_logs=${pod_logs:-0}

    log_info "Found $secret_logs secret-related audit entries"
    log_info "Found $pod_logs pod-related audit entries"

    if [[ $secret_logs -gt 0 && $pod_logs -gt 0 ]]; then
        log_success "Audit logging is working correctly!"

        # Show sample logs
        log_info "Sample secret audit log entry:"
        docker exec "$CONTROL_PLANE_CONTAINER" bash -c 'grep "\"secrets\"" /var/log/kubernetes/audit.log | head -1 | jq .' || true

        log_info "Sample pod audit log entry:"
        docker exec "$CONTROL_PLANE_CONTAINER" bash -c 'grep "\"pods\"" /var/log/kubernetes/audit.log | head -1 | jq .' || true
    else
        log_warning "Audit logs may not be working as expected"
        log_info "Showing last 5 audit log entries:"
        docker exec "$CONTROL_PLANE_CONTAINER" bash -c 'tail -5 /var/log/kubernetes/audit.log | jq .' || true
    fi

    # Clean up test resources
    log_info "Cleaning up test resources..."
    kubectl delete secret test-audit-secret --ignore-not-found=true
    kubectl delete pod test-audit-pod --ignore-not-found=true

    log_success "Test completed"
}

# Function to verify audit configuration
verify_audit_configuration() {
    log_info "Verifying audit configuration..."

    # Check if audit policy exists
    if docker exec "$CONTROL_PLANE_CONTAINER" test -f /etc/kubernetes/audit-policy.yaml; then
        log_success "Audit policy file exists"
        log_info "Audit policy content:"
        docker exec "$CONTROL_PLANE_CONTAINER" cat /etc/kubernetes/audit-policy.yaml
    else
        log_error "Audit policy file not found"
        return 1
    fi

    # Check if API server manifest has audit flags
    local audit_flags_count
    audit_flags_count=$(docker exec "$CONTROL_PLANE_CONTAINER" bash -c 'grep -c "audit" /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null || echo "0"')

    # Ensure it's a valid number by taking only the first line and removing any whitespace
    audit_flags_count=$(echo "$audit_flags_count" | head -1 | tr -d '[:space:]')
    audit_flags_count=${audit_flags_count:-0}

    if [[ $audit_flags_count -gt 0 ]]; then
        log_success "Audit configuration found in API server manifest"
        log_info "Audit-related lines in manifest:"
        docker exec "$CONTROL_PLANE_CONTAINER" bash -c 'grep -n "audit" /etc/kubernetes/manifests/kube-apiserver.yaml' || true
    else
        log_error "No audit configuration found in API server manifest"
        return 1
    fi

    # Check if audit log directory exists
    if docker exec "$CONTROL_PLANE_CONTAINER" test -d /var/log/kubernetes; then
        log_success "Audit log directory exists"
    else
        log_error "Audit log directory not found"
        return 1
    fi

    return 0
}

# Function to restore original configuration
restore_original_config() {
    log_info "Restoring original API server configuration..."

    if [[ -f "$ORIGINAL_MANIFEST_BACKUP" ]]; then
        docker cp "$ORIGINAL_MANIFEST_BACKUP" "$CONTROL_PLANE_CONTAINER:/etc/kubernetes/manifests/kube-apiserver.yaml"
        log_success "Restored original API server manifest"

        log_info "Waiting for API server to restart..."
        wait_for_api_server

        # Clean up audit policy
        docker exec "$CONTROL_PLANE_CONTAINER" rm -f /etc/kubernetes/audit-policy.yaml
        log_success "Removed audit policy file"

        log_success "Original configuration restored"
    else
        log_error "Backup file $ORIGINAL_MANIFEST_BACKUP not found"
        return 1
    fi
}

# Function to cleanup
cleanup() {
    log_info "Cleaning up..."

    # Remove test resources if they exist
    kubectl delete secret test-audit-secret --ignore-not-found=true >/dev/null 2>&1 || true
    kubectl delete pod test-audit-pod --ignore-not-found=true >/dev/null 2>&1 || true

    log_success "Cleanup completed"
}

# Function to show help
show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

This script automates the Kubernetes Audit Logs lab for kind clusters.

OPTIONS:
    -h, --help      Show this help message
    -c, --cleanup   Only run cleanup (remove test resources)
    -r, --restore   Restore original API server configuration
    -v, --verify    Only verify the current audit configuration
    -t, --test      Only run the audit logs test

EXAMPLES:
    $0              Run the complete lab
    $0 --verify     Check if audit logging is already configured
    $0 --test       Test audit logging with sample resources
    $0 --restore    Restore original API server configuration
    $0 --cleanup    Clean up test resources

EOF
}

# Main function
main() {
    log_info "Starting Kubernetes Audit Logs Lab Automation"
    log_info "=============================================="

    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--cleanup)
            detect_control_plane
            cleanup
            exit 0
            ;;
        -r|--restore)
            detect_control_plane
            restore_original_config
            exit 0
            ;;
        -v|--verify)
            detect_control_plane
            verify_audit_configuration
            exit 0
            ;;
        -t|--test)
            detect_control_plane
            test_audit_logs
            exit 0
            ;;
        "")
            # Run complete lab
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac

    # Trap to ensure cleanup on script exit
    trap cleanup EXIT

    # Step 0: Python YAML check is handled within modify_api_server_manifest

    # Step 1: Detect control plane container
    detect_control_plane

    # Step 1.5: Check if audit is already configured
    if verify_audit_configuration >/dev/null 2>&1; then
        log_warning "Audit logging appears to be already configured"
        read -p "Continue anyway? (y/N): " continue_anyway
        if [[ "${continue_anyway,,}" != "y" ]]; then
            log_info "Exiting without changes"
            exit 0
        fi
    fi

    # Step 2: Backup API server manifest
    backup_api_server_manifest

    # Step 3: Create audit policy
    create_audit_policy

    # Step 4: Modify API server manifest
    modify_api_server_manifest

    # Step 5: Wait for API server to restart
    wait_for_api_server

    # Step 6: Verify configuration
    verify_audit_configuration

    # Step 7: Test audit logs
    test_audit_logs

    log_success "=============================================="
    log_success "Audit Logs Lab completed successfully!"
    log_success "=============================================="
    log_info "To restore original configuration, run: $0 --restore"
    log_info "To test again, run: $0 --test"
    log_info "To verify configuration, run: $0 --verify"
}

# Check if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi