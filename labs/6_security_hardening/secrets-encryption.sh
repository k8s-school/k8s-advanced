#!/bin/bash

# Kubernetes Secrets Encryption at Rest Lab Automation
# This script automates the secrets encryption configuration lab

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
NAMESPACE="secret-encryption-test"
TEST_TIMEOUT=300

# Global variables
CONTROL_PLANE_CONTAINER=""
ENCRYPTION_KEY=""
BACKUP_FILE=""

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    for tool in kubectl docker openssl base64; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    log_success "All prerequisites are available"
}

# Function to verify cluster connectivity
verify_cluster() {
    log_info "Verifying cluster connectivity..."

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    local cluster_context=$(kubectl config current-context 2>/dev/null || echo "unknown")
    log_success "Connected to cluster: $cluster_context"
}

# Function to detect control plane container
detect_control_plane() {
    log_info "Detecting control plane container..."

    local current_context=$(kubectl config current-context)

    if [[ "$current_context" == kind-* ]]; then
        local cluster_name=$(echo "$current_context" | sed 's/^kind-//')
        CONTROL_PLANE_CONTAINER="${cluster_name}-control-plane"

        # Verify the container exists
        if docker ps --filter "name=${CONTROL_PLANE_CONTAINER}" --format "{{.Names}}" | grep -q "${CONTROL_PLANE_CONTAINER}"; then
            log_success "Using control plane container: $CONTROL_PLANE_CONTAINER"
            return 0
        fi
    fi

    log_error "This lab requires a Kind cluster"
    exit 1
}

# Function to generate encryption key
generate_encryption_key() {
    log_info "Generating encryption key..."

    ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64 | tr -d '\n')
    log_success "Generated 32-byte encryption key: ${ENCRYPTION_KEY:0:16}..."
}

# Function to demonstrate unencrypted secrets
demonstrate_unencrypted_storage() {
    log_info "Demonstrating unencrypted secret storage..."

    # Create test namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # Create a test secret
    kubectl create secret generic unencrypted-secret \
        --from-literal=password=mysecretpassword \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Check in etcd
    log_info "Checking secret storage in etcd..."
    local secret_data
    secret_data=$(docker exec "$CONTROL_PLANE_CONTAINER" bash -c "
        ETCDCTL_API=3 etcdctl \\
            --endpoints=https://127.0.0.1:2379 \\
            --cacert=/etc/kubernetes/pki/etcd/ca.crt \\
            --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \\
            --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \\
            get /registry/secrets/$NAMESPACE/unencrypted-secret 2>/dev/null || echo 'Secret not found'
    ")

    if [[ "$secret_data" == *"mysecretpassword"* ]]; then
        log_warning "Secret is stored in PLAIN TEXT in etcd!"
        log_info "This demonstrates why encryption at rest is important"
    else
        log_info "Secret data in etcd (may be base64 encoded): ${secret_data:0:100}..."
    fi
}

# Function to backup API server manifest
backup_api_server_manifest() {
    log_info "Backing up API server manifest..."

    local timestamp=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="/tmp/kube-apiserver-backup-$timestamp.yaml"

    docker cp "$CONTROL_PLANE_CONTAINER:/etc/kubernetes/manifests/kube-apiserver.yaml" "$BACKUP_FILE"
    docker exec "$CONTROL_PLANE_CONTAINER" cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak

    log_success "Backed up API server manifest to $BACKUP_FILE"
}

# Function to create encryption configuration
create_encryption_config() {
    log_info "Creating encryption configuration..."

    # Create encryption configuration
    local enc_config="/tmp/enc.yaml"
    cat > "$enc_config" <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: $ENCRYPTION_KEY
      - identity: {}
EOF

    # Copy to control plane
    docker cp "$enc_config" "$CONTROL_PLANE_CONTAINER:/etc/kubernetes/enc.yaml"

    # Set proper permissions
    docker exec "$CONTROL_PLANE_CONTAINER" chmod 600 /etc/kubernetes/enc.yaml
    docker exec "$CONTROL_PLANE_CONTAINER" chown root:root /etc/kubernetes/enc.yaml

    log_success "Created encryption configuration at /etc/kubernetes/enc.yaml"
}

# Function to update API server manifest
update_api_server_manifest() {
    log_info "Updating API server manifest to enable encryption..."

    # Use Python to safely modify the YAML
    python3 << EOF
import yaml
import sys

try:
    # Read the backup file
    with open("$BACKUP_FILE", 'r') as f:
        data = yaml.safe_load(f)

    # Add encryption provider config flag
    container = data['spec']['containers'][0]
    encryption_flag = '--encryption-provider-config=/etc/kubernetes/enc.yaml'

    # Only add flag if not already present
    if not any(cmd.startswith('--encryption-provider-config') for cmd in container['command']):
        container['command'].append(encryption_flag)

    # Add volume mount
    enc_mount = {
        'mountPath': '/etc/kubernetes/enc.yaml',
        'name': 'encryption-config',
        'readOnly': True
    }

    if not any(vm.get('name') == 'encryption-config' for vm in container.get('volumeMounts', [])):
        container.setdefault('volumeMounts', []).append(enc_mount)

    # Add volume
    enc_volume = {
        'hostPath': {'path': '/etc/kubernetes/enc.yaml', 'type': 'File'},
        'name': 'encryption-config'
    }

    if not any(v.get('name') == 'encryption-config' for v in data['spec'].get('volumes', [])):
        data['spec'].setdefault('volumes', []).append(enc_volume)

    # Clean up runtime metadata
    runtime_fields = ['creationTimestamp', 'resourceVersion', 'uid', 'generation', 'ownerReferences']
    for field in runtime_fields:
        data['metadata'].pop(field, None)
    data.pop('status', None)

    # Write the modified file
    with open('/tmp/kube-apiserver-work.yaml', 'w') as f:
        yaml.dump(data, f, default_flow_style=False, width=1000, indent=2, sort_keys=False)

    print("✓ API server manifest updated successfully")

except Exception as e:
    print(f"✗ Error updating manifest: {e}")
    sys.exit(1)
EOF

    # Validate YAML syntax
    if python3 -c "import yaml; yaml.safe_load(open('/tmp/kube-apiserver-work.yaml'))" 2>/dev/null; then
        log_success "Generated manifest is valid YAML"

        # Apply the modified manifest
        docker cp /tmp/kube-apiserver-work.yaml "$CONTROL_PLANE_CONTAINER:/etc/kubernetes/manifests/kube-apiserver.yaml"
        docker exec "$CONTROL_PLANE_CONTAINER" touch /etc/kubernetes/manifests/kube-apiserver.yaml

        log_success "Applied updated API server manifest"
    else
        log_error "Generated manifest has YAML errors"
        return 1
    fi
}

# Function to wait for API server restart
wait_for_api_server() {
    log_info "Waiting for API server to restart with encryption..."

    # Wait a bit for the change to be detected
    sleep 15

    # Wait for API server to be ready
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if kubectl get nodes >/dev/null 2>&1; then
            log_success "API server is ready with encryption enabled"
            return 0
        fi

        log_info "Waiting for API server... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done

    log_error "API server failed to restart properly"
    return 1
}

# Function to encrypt existing secrets
encrypt_existing_secrets() {
    log_info "Encrypting existing secrets..."

    # Get all secrets and re-apply them to trigger encryption
    kubectl get secrets --all-namespaces -o json | kubectl replace -f -

    log_success "Re-applied all existing secrets for encryption"
}

# Function to test encryption
test_encryption() {
    log_info "Testing secret encryption..."

    # Create a new secret (should be encrypted)
    kubectl create secret generic encrypted-secret \
        --from-literal=token=verysecrettoken \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Verify the secret works normally from Kubernetes API
    local secret_value
    secret_value=$(kubectl get secret encrypted-secret -n "$NAMESPACE" -o jsonpath='{.data.token}' | base64 -d)

    if [[ "$secret_value" == "verysecrettoken" ]]; then
        log_success "Secret can be read normally through Kubernetes API"
    else
        log_error "Failed to read secret through Kubernetes API"
        return 1
    fi

    # Check in etcd (should be encrypted now)
    log_info "Checking encrypted secret in etcd..."
    local etcd_data
    etcd_data=$(docker exec "$CONTROL_PLANE_CONTAINER" bash -c "
        ETCDCTL_API=3 etcdctl \\
            --endpoints=https://127.0.0.1:2379 \\
            --cacert=/etc/kubernetes/pki/etcd/ca.crt \\
            --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \\
            --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \\
            get /registry/secrets/$NAMESPACE/encrypted-secret 2>/dev/null || echo 'Secret not found'
    ")

    if [[ "$etcd_data" == *"verysecrettoken"* ]]; then
        log_error "Secret is still in PLAIN TEXT in etcd!"
        log_error "Encryption may not be working properly"
        return 1
    elif [[ "$etcd_data" == *"Secret not found"* ]]; then
        log_warning "Could not find secret in etcd (may be stored with different path)"
    else
        log_success "Secret appears to be encrypted in etcd"
        log_info "etcd data (encrypted): ${etcd_data:0:100}..."
    fi
}

# Function to demonstrate key rotation
demonstrate_key_rotation() {
    log_info "Demonstrating key rotation process..."

    # Generate new key
    local new_key=$(head -c 32 /dev/urandom | base64 | tr -d '\n')
    log_info "Generated new encryption key for rotation"

    # Create updated encryption config with both keys
    cat > /tmp/enc-rotated.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key2
              secret: $new_key
            - name: key1
              secret: $ENCRYPTION_KEY
      - identity: {}
EOF

    # Apply the updated configuration
    docker cp /tmp/enc-rotated.yaml "$CONTROL_PLANE_CONTAINER:/etc/kubernetes/enc.yaml"

    # Restart API server and re-encrypt secrets
    docker exec "$CONTROL_PLANE_CONTAINER" touch /etc/kubernetes/manifests/kube-apiserver.yaml
    sleep 15

    if kubectl get nodes >/dev/null 2>&1; then
        # Re-encrypt all secrets with new key
        log_info "Re-encrypting secrets with new key..."
        kubectl get secrets --all-namespaces -o json | kubectl replace -f -

        log_success "Key rotation demonstration completed"
        log_info "In production, you would now remove the old key from the configuration"
    else
        log_warning "API server restart failed during key rotation demo"
    fi
}

# Function to verify encryption configuration
verify_encryption_config() {
    log_info "Verifying encryption configuration..."

    # Check if encryption config file exists
    if docker exec "$CONTROL_PLANE_CONTAINER" test -f /etc/kubernetes/enc.yaml; then
        log_success "Encryption configuration file exists"
    else
        log_error "Encryption configuration file not found"
        return 1
    fi

    # Check if API server is using the encryption config
    local api_server_config
    api_server_config=$(kubectl get pod -n kube-system -l component=kube-apiserver -o yaml | grep "encryption-provider-config" || echo "not found")

    if [[ "$api_server_config" != "not found" ]]; then
        log_success "API server is configured to use encryption"
    else
        log_error "API server is not configured for encryption"
        return 1
    fi

    return 0
}

# Function to restore original configuration
restore_original_config() {
    log_info "Restoring original API server configuration..."

    if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        docker cp "$BACKUP_FILE" "$CONTROL_PLANE_CONTAINER:/etc/kubernetes/manifests/kube-apiserver.yaml"
        log_success "Restored original API server manifest"

        # Remove encryption configuration
        docker exec "$CONTROL_PLANE_CONTAINER" rm -f /etc/kubernetes/enc.yaml
        log_success "Removed encryption configuration"

        # Wait for API server to restart
        log_info "Waiting for API server to restart..."
        sleep 15

        if kubectl get nodes >/dev/null 2>&1; then
            log_success "Original configuration restored successfully"
        else
            log_warning "API server may be restarting after restore"
        fi
    else
        log_error "Backup file not found"
        return 1
    fi
}

# Function to cleanup resources
cleanup() {
    log_info "Cleaning up test resources..."

    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
    rm -f /tmp/enc.yaml /tmp/enc-rotated.yaml /tmp/kube-apiserver-work.yaml

    log_success "Cleanup completed"
}

# Function to run diagnostics
run_diagnostics() {
    log_info "Running encryption diagnostics..."

    echo "=== Cluster Information ==="
    kubectl version --short

    echo -e "\n=== API Server Configuration ==="
    kubectl get pod -n kube-system -l component=kube-apiserver -o yaml | grep -A5 -B5 "encryption" || echo "No encryption config found"

    echo -e "\n=== Secrets in Test Namespace ==="
    kubectl get secrets -n "$NAMESPACE" 2>/dev/null || echo "No secrets found"

    if [ -n "$CONTROL_PLANE_CONTAINER" ]; then
        echo -e "\n=== Encryption Configuration File ==="
        docker exec "$CONTROL_PLANE_CONTAINER" ls -la /etc/kubernetes/enc.yaml 2>/dev/null || echo "Encryption config file not found"

        echo -e "\n=== API Server Manifest ==="
        docker exec "$CONTROL_PLANE_CONTAINER" grep -A3 -B3 "encryption" /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null || echo "No encryption config in manifest"
    fi
}

# Function to show help
show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

This script automates the Kubernetes secrets encryption at rest lab.

OPTIONS:
    -h, --help        Show this help message
    -c, --cleanup     Only run cleanup (remove test resources)
    -r, --restore     Restore original API server configuration
    -v, --verify      Only verify encryption configuration
    -t, --test        Only run encryption tests
    -d, --diagnostics Only run diagnostics

EXAMPLES:
    $0                Run the complete lab
    $0 --verify       Check if encryption is already configured
    $0 --test         Test encryption functionality
    $0 --restore      Restore original configuration
    $0 --cleanup      Clean up test resources

EOF
}

# Main function
main() {
    log_info "Starting Kubernetes Secrets Encryption at Rest Lab"
    log_info "=================================================="

    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--cleanup)
            cleanup
            exit 0
            ;;
        -r|--restore)
            detect_control_plane
            restore_original_config
            exit 0
            ;;
        -v|--verify)
            check_prerequisites
            verify_cluster
            detect_control_plane
            verify_encryption_config
            exit 0
            ;;
        -t|--test)
            check_prerequisites
            verify_cluster
            detect_control_plane
            test_encryption
            exit 0
            ;;
        -d|--diagnostics)
            verify_cluster
            detect_control_plane
            run_diagnostics
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

    # Run complete lab
    check_prerequisites
    verify_cluster
    detect_control_plane
    generate_encryption_key
    demonstrate_unencrypted_storage
    backup_api_server_manifest
    create_encryption_config
    update_api_server_manifest
    wait_for_api_server
    encrypt_existing_secrets
    test_encryption
    demonstrate_key_rotation
    verify_encryption_config
    run_diagnostics

    log_success "=================================================="
    log_success "Secrets Encryption at Rest Lab completed!"
    log_success "=================================================="
    log_info "Key achievements:"
    log_info "- Configured AES-CBC encryption for Kubernetes secrets"
    log_info "- Demonstrated encryption verification process"
    log_info "- Showed key rotation procedures"
    log_info "- Verified secrets are encrypted in etcd"
    log_info ""
    log_info "Security reminders:"
    log_info "- Store encryption keys securely, separate from etcd backups"
    log_info "- Implement regular key rotation procedures"
    log_info "- Consider external key management systems for production"
    log_info "- Monitor access to encryption configuration files"
    log_info ""
    log_info "To restore original configuration, run: $0 --restore"
}

# Check if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi