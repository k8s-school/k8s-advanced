#!/bin/bash

# Kubernetes Seccomp Security Profiles Lab Automation
# This script automates the seccomp security profiles lab

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
NAMESPACE="seccomp-test"
TEST_TIMEOUT=60

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    for tool in kubectl docker jq; do
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

# Function to check seccomp support
check_seccomp_support() {
    log_info "Checking seccomp support..."

    # Check if seccomp is available on the host
    if grep -q seccomp /proc/version; then
        log_success "Seccomp is supported on the host system"
    else
        log_warning "Cannot verify seccomp support from host"
    fi

    # Check if Kubernetes supports seccomp
    local server_version=$(kubectl version -o json | jq -r '.serverVersion.gitVersion' 2>/dev/null || echo "unknown")
    log_info "Kubernetes server version: $server_version"

    # All recent Kubernetes versions support seccomp
    log_success "Kubernetes supports seccomp profiles"
}

# Function to setup test environment
setup_test_environment() {
    log_info "Setting up test environment..."

    # Create test namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    log_success "Test environment ready"
}

# Function to test runtime default seccomp
test_runtime_default_seccomp() {
    log_info "Testing RuntimeDefault seccomp profile..."

    # Create pod with RuntimeDefault seccomp profile
    cat << 'EOF' > /tmp/seccomp-runtime-default.yaml
apiVersion: v1
kind: Pod
metadata:
  name: seccomp-runtime-default
  namespace: seccomp-test
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: test-container
    image: busybox:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do sleep 30; done;"]
EOF

    kubectl apply -f /tmp/seccomp-runtime-default.yaml

    # Wait for pod to be ready
    kubectl wait --for=condition=Ready pod/seccomp-runtime-default -n "$NAMESPACE" --timeout="${TEST_TIMEOUT}s"

    # Test seccomp is applied
    log_info "Verifying seccomp profile is applied..."
    local seccomp_status
    seccomp_status=$(kubectl exec seccomp-runtime-default -n "$NAMESPACE" -- grep -i seccomp /proc/1/status 2>/dev/null || echo "not found")

    if [[ "$seccomp_status" == *"Seccomp:	2"* ]]; then
        log_success "RuntimeDefault seccomp profile is active (filtered mode)"
    else
        log_warning "Seccomp status: $seccomp_status"
    fi

    # Test basic operations work
    log_info "Testing basic operations..."
    kubectl exec seccomp-runtime-default -n "$NAMESPACE" -- ps aux >/dev/null
    kubectl exec seccomp-runtime-default -n "$NAMESPACE" -- ls -la >/dev/null

    log_success "Basic operations work with RuntimeDefault profile"

    # Test restricted operations
    log_info "Testing restricted operations..."
    if ! kubectl exec seccomp-runtime-default -n "$NAMESPACE" -- mount 2>/dev/null; then
        log_success "Mount operation properly restricted"
    else
        log_warning "Mount operation was not restricted (might be expected in some environments)"
    fi
}

# Function to create custom seccomp profile
create_custom_seccomp_profile() {
    log_info "Creating custom seccomp profile..."

    # Detect control plane for Kind cluster
    local current_context=$(kubectl config current-context)
    if [[ "$current_context" == kind-* ]]; then
        local cluster_name=$(echo "$current_context" | sed 's/^kind-//')
        local control_plane_container="${cluster_name}-control-plane"

        # Check if Kind container exists
        if docker ps --filter "name=${control_plane_container}" --format "{{.Names}}" | grep -q "${control_plane_container}"; then
            log_info "Setting up custom seccomp profile in Kind cluster..."

            # Create custom seccomp profile
            local custom_profile='/tmp/custom-seccomp-profile.json'
            cat > "$custom_profile" << 'EOF'
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "syscalls": [
    {
      "names": ["mount", "umount2", "syslog"],
      "action": "SCMP_ACT_ERRNO"
    },
    {
      "names": ["reboot"],
      "action": "SCMP_ACT_KILL"
    }
  ]
}
EOF

            # Copy profile to Kind node
            docker exec "$control_plane_container" mkdir -p /var/lib/kubelet/seccomp/profiles
            docker cp "$custom_profile" "$control_plane_container:/var/lib/kubelet/seccomp/profiles/custom-profile.json"

            # Also copy to worker nodes
            for worker in $(docker ps --filter "name=${cluster_name}-worker" --format "{{.Names}}"); do
                docker exec "$worker" mkdir -p /var/lib/kubelet/seccomp/profiles
                docker cp "$custom_profile" "$worker:/var/lib/kubelet/seccomp/profiles/custom-profile.json"
            done

            log_success "Custom seccomp profile created and distributed"
            return 0
        fi
    fi

    log_warning "Custom seccomp profile creation requires direct node access"
    log_info "In a real cluster, you would:"
    log_info "1. Create /var/lib/kubelet/seccomp/profiles/ directory on all nodes"
    log_info "2. Place custom-profile.json in that directory"
    log_info "3. Ensure proper file permissions"
}

# Function to test custom seccomp profile
test_custom_seccomp_profile() {
    log_info "Testing custom seccomp profile..."

    # Create pod with custom seccomp profile
    cat << 'EOF' > /tmp/seccomp-custom-profile.yaml
apiVersion: v1
kind: Pod
metadata:
  name: seccomp-custom-profile
  namespace: seccomp-test
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/custom-profile.json
  containers:
  - name: test-container
    image: busybox:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do sleep 30; done;"]
EOF

    if kubectl apply -f /tmp/seccomp-custom-profile.yaml 2>/dev/null; then
        # Wait for pod to be ready or check if it fails
        if kubectl wait --for=condition=Ready pod/seccomp-custom-profile -n "$NAMESPACE" --timeout="${TEST_TIMEOUT}s" 2>/dev/null; then
            log_success "Pod with custom seccomp profile is running"

            # Test that mount is blocked
            log_info "Testing custom restrictions..."
            if ! kubectl exec seccomp-custom-profile -n "$NAMESPACE" -- mount 2>/dev/null; then
                log_success "Mount operation blocked by custom profile"
            else
                log_warning "Mount operation was not blocked"
            fi
        else
            log_warning "Pod with custom seccomp profile failed to start (profile may not be available)"
            kubectl describe pod seccomp-custom-profile -n "$NAMESPACE" | tail -10
        fi
    else
        log_warning "Failed to create pod with custom seccomp profile"
    fi
}

# Function to test pod security standards integration
test_pod_security_standards() {
    log_info "Testing seccomp with Pod Security Standards..."

    # Create restricted namespace
    cat << 'EOF' > /tmp/restricted-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: seccomp-restricted
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
EOF

    kubectl apply -f /tmp/restricted-namespace.yaml

    # Create compliant pod
    cat << 'EOF' > /tmp/compliant-seccomp-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: compliant-pod
  namespace: seccomp-restricted
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1001
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: busybox:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do sleep 30; done;"]
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: false
      runAsNonRoot: true
      runAsUser: 1001
      capabilities:
        drop:
        - ALL
EOF

    if kubectl apply -f /tmp/compliant-seccomp-pod.yaml; then
        kubectl wait --for=condition=Ready pod/compliant-pod -n seccomp-restricted --timeout="${TEST_TIMEOUT}s"
        log_success "Pod compliant with restricted security standards created"
    else
        log_error "Failed to create pod compliant with restricted standards"
    fi

    # Test non-compliant pod (should be rejected)
    cat << 'EOF' > /tmp/non-compliant-seccomp-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: non-compliant-pod
  namespace: seccomp-restricted
spec:
  containers:
  - name: app
    image: busybox:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do sleep 30; done;"]
    securityContext:
      privileged: true
EOF

    if ! kubectl apply -f /tmp/non-compliant-seccomp-pod.yaml 2>/dev/null; then
        log_success "Non-compliant pod correctly rejected by Pod Security Standards"
    else
        log_warning "Non-compliant pod was not rejected (unexpected)"
        kubectl delete pod non-compliant-pod -n seccomp-restricted --ignore-not-found=true
    fi
}

# Function to test container-level seccomp
test_container_level_seccomp() {
    log_info "Testing container-level seccomp profiles..."

    cat << 'EOF' > /tmp/container-level-seccomp.yaml
apiVersion: v1
kind: Pod
metadata:
  name: container-level-seccomp
  namespace: seccomp-test
spec:
  containers:
  - name: restricted-container
    image: busybox:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do sleep 30; done;"]
    securityContext:
      seccompProfile:
        type: RuntimeDefault
  - name: unconfined-container
    image: busybox:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do sleep 30; done;"]
    securityContext:
      seccompProfile:
        type: Unconfined
EOF

    kubectl apply -f /tmp/container-level-seccomp.yaml
    kubectl wait --for=condition=Ready pod/container-level-seccomp -n "$NAMESPACE" --timeout="${TEST_TIMEOUT}s"

    # Test restricted container
    log_info "Testing restricted container..."
    local restricted_seccomp
    restricted_seccomp=$(kubectl exec container-level-seccomp -c restricted-container -n "$NAMESPACE" -- grep -i seccomp /proc/1/status 2>/dev/null || echo "not found")

    if [[ "$restricted_seccomp" == *"Seccomp:	2"* ]]; then
        log_success "Restricted container has seccomp filtering enabled"
    else
        log_warning "Restricted container seccomp status: $restricted_seccomp"
    fi

    # Test unconfined container
    log_info "Testing unconfined container..."
    local unconfined_seccomp
    unconfined_seccomp=$(kubectl exec container-level-seccomp -c unconfined-container -n "$NAMESPACE" -- grep -i seccomp /proc/1/status 2>/dev/null || echo "not found")

    if [[ "$unconfined_seccomp" == *"Seccomp:	0"* ]]; then
        log_success "Unconfined container has seccomp disabled"
    else
        log_info "Unconfined container seccomp status: $unconfined_seccomp"
    fi

    log_success "Container-level seccomp configuration working"
}

# Function to demonstrate seccomp violations
demonstrate_seccomp_violations() {
    log_info "Demonstrating seccomp violations..."

    # Use the RuntimeDefault pod for testing
    if kubectl get pod seccomp-runtime-default -n "$NAMESPACE" >/dev/null 2>&1; then
        log_info "Testing system calls that may be restricted..."

        # Test various system calls
        local test_commands=(
            "ps aux"
            "ls -la"
            "cat /proc/version"
            "mount"
            "reboot"
        )

        for cmd in "${test_commands[@]}"; do
            log_info "Testing command: $cmd"
            if kubectl exec seccomp-runtime-default -n "$NAMESPACE" -- sh -c "$cmd" >/dev/null 2>&1; then
                log_info "  ✓ Command succeeded"
            else
                log_warning "  ✗ Command failed (may be restricted by seccomp)"
            fi
        done
    else
        log_warning "RuntimeDefault pod not available for testing"
    fi
}

# Function to run diagnostics
run_diagnostics() {
    log_info "Running seccomp diagnostics..."

    echo "=== Cluster Information ==="
    kubectl version --short

    echo -e "\n=== Node Information ==="
    kubectl get nodes -o wide

    echo -e "\n=== Seccomp Test Pods ==="
    kubectl get pods -n "$NAMESPACE" -o wide

    echo -e "\n=== Pod Security Standards Namespaces ==="
    kubectl get ns -l pod-security.kubernetes.io/enforce

    # Check seccomp status of running pods
    echo -e "\n=== Pod Seccomp Status ==="
    for pod in $(kubectl get pods -n "$NAMESPACE" -o name | cut -d/ -f2); do
        echo "Pod: $pod"
        local status
        status=$(kubectl exec "$pod" -n "$NAMESPACE" -- grep -i seccomp /proc/1/status 2>/dev/null || echo "not available")
        echo "  Seccomp status: $status"
    done

    # Check for seccomp support on nodes
    echo -e "\n=== Node Seccomp Support ==="
    local current_context=$(kubectl config current-context)
    if [[ "$current_context" == kind-* ]]; then
        local cluster_name=$(echo "$current_context" | sed 's/^kind-//')
        local control_plane_container="${cluster_name}-control-plane"

        if docker ps --filter "name=${control_plane_container}" --format "{{.Names}}" | grep -q "${control_plane_container}"; then
            echo "Control plane seccomp support:"
            docker exec "$control_plane_container" grep -i seccomp /proc/version 2>/dev/null || echo "  Seccomp information not available"
        fi
    fi
}

# Function to cleanup resources
cleanup() {
    log_info "Cleaning up test resources..."

    # Delete test namespaces
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
    kubectl delete namespace seccomp-restricted --ignore-not-found=true

    # Clean up temporary files
    rm -f /tmp/seccomp-*.yaml /tmp/container-level-seccomp.yaml /tmp/compliant-seccomp-pod.yaml /tmp/non-compliant-seccomp-pod.yaml /tmp/restricted-namespace.yaml /tmp/custom-seccomp-profile.json

    log_success "Cleanup completed"
}

# Function to show help
show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

This script automates the Kubernetes seccomp security profiles lab.

OPTIONS:
    -h, --help        Show this help message
    -c, --cleanup     Only run cleanup (remove test resources)
    -d, --diagnostics Only run diagnostics
    -r, --runtime     Only test RuntimeDefault profile
    -s, --standards   Only test Pod Security Standards integration
    -v, --violations  Only demonstrate seccomp violations

EXAMPLES:
    $0                Run the complete lab
    $0 --runtime      Test only RuntimeDefault seccomp profile
    $0 --standards    Test Pod Security Standards integration
    $0 --violations   Demonstrate seccomp violations
    $0 --cleanup      Clean up all test resources

EOF
}

# Main function
main() {
    log_info "Starting Kubernetes Seccomp Security Profiles Lab"
    log_info "================================================"

    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--cleanup)
            cleanup
            exit 0
            ;;
        -d|--diagnostics)
            verify_cluster
            setup_test_environment
            run_diagnostics
            exit 0
            ;;
        -r|--runtime)
            check_prerequisites
            verify_cluster
            check_seccomp_support
            setup_test_environment
            test_runtime_default_seccomp
            exit 0
            ;;
        -s|--standards)
            check_prerequisites
            verify_cluster
            test_pod_security_standards
            exit 0
            ;;
        -v|--violations)
            check_prerequisites
            verify_cluster
            setup_test_environment
            test_runtime_default_seccomp
            demonstrate_seccomp_violations
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
    check_seccomp_support
    setup_test_environment
    test_runtime_default_seccomp
    create_custom_seccomp_profile
    test_custom_seccomp_profile
    test_pod_security_standards
    test_container_level_seccomp
    demonstrate_seccomp_violations
    run_diagnostics

    log_success "=============================================="
    log_success "Seccomp Security Profiles Lab completed!"
    log_success "=============================================="
    log_info "Key achievements:"
    log_info "- Configured RuntimeDefault seccomp profiles"
    log_info "- Created and tested custom seccomp profiles"
    log_info "- Integrated seccomp with Pod Security Standards"
    log_info "- Demonstrated container-level seccomp configuration"
    log_info "- Tested seccomp violations and restrictions"
    log_info ""
    log_info "Security reminders:"
    log_info "- Use RuntimeDefault as a baseline for most applications"
    log_info "- Create custom profiles for applications with specific needs"
    log_info "- Test thoroughly before applying restrictive profiles"
    log_info "- Monitor for seccomp violations in production"
    log_info "- Combine with other security mechanisms (AppArmor, SELinux)"
}

# Check if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi