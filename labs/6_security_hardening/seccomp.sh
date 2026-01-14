#!/bin/bash
set -euo pipefail

# Parse command line arguments
CLEANUP=false
STOP_AFTER_CLUSTER=true
CLUSTER_NAME="$(whoami)-seccomp-lab"

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cleanup)
            CLEANUP=true
            shift
            ;;
        -s|--skip-stop)
            STOP_AFTER_CLUSTER=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -c, --cleanup      Automatically cleanup resources at the end"
            echo "  -s, --skip-stop    Continue with full tutorial (default: stop after cluster creation)"
            echo "  -h, --help         Show this help message"
            echo ""
            echo "By default, the script stops after cluster creation for manual experimentation."
            echo "Use -s to run the complete automated tutorial."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

echo "=== Kubernetes Seccomp Tutorial ==="
echo "This script reproduces the official Kubernetes seccomp tutorial"
echo "Source: https://kubernetes.io/docs/tutorials/security/seccomp/"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

function log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

function log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Prerequisites check
log_info "Checking prerequisites..."
command -v kind >/dev/null 2>&1 || { log_error "kind is not installed"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { log_error "kubectl is not installed"; exit 1; }
command -v docker >/dev/null 2>&1 || { log_error "docker is not installed"; exit 1; }
log_success "All prerequisites are met"

# Step 1: Create working directory and download profiles
log_info "Step 1: Setting up seccomp profiles"
LAB_DIR="$HOME/seccomp_lab"
PROFILES_PATH="$LAB_DIR/profiles"
mkdir -p "$PROFILES_PATH"

log_info "Lab directory: $LAB_DIR"

log_info "Downloading seccomp profiles from Kubernetes official examples..."

# Base URLs for Kubernetes website examples
BASE_URL="https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/pods/security/seccomp/profiles"
PODS_BASE_URL="https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/pods/security/seccomp/ga"

# Download audit profile
log_info "Command: curl -L -o $PROFILES_PATH/audit.json $BASE_URL/audit.json"
if curl -L -o "$PROFILES_PATH/audit.json" "$BASE_URL/audit.json"; then
    log_success "Downloaded audit.json (logs all syscalls)"
else
    log_error "Failed to download audit.json"
    exit 1
fi

# Download violation profile
log_info "Command: curl -L -o $PROFILES_PATH/violation.json $BASE_URL/violation.json"
if curl -L -o "$PROFILES_PATH/violation.json" "$BASE_URL/violation.json"; then
    log_success "Downloaded violation.json (blocks all syscalls)"
else
    log_error "Failed to download violation.json"
    exit 1
fi

# Download fine-grained profile
log_info "Command: curl -L -o $PROFILES_PATH/fine-grained.json $BASE_URL/fine-grained.json"
if curl -L -o "$PROFILES_PATH/fine-grained.json" "$BASE_URL/fine-grained.json"; then
    log_success "Downloaded fine-grained.json (allows specific syscalls)"
else
    log_error "Failed to download fine-grained.json"
    exit 1
fi

# Step 2: Create kind cluster configuration
log_info "Step 2: Setting up Kubernetes cluster with kind"

cat << EOF > "$LAB_DIR/kind-config.yaml"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: ${PROFILES_PATH}
    containerPath: /var/lib/kubelet/seccomp/profiles
    readOnly: true
- role: worker
  extraMounts:
  - hostPath: ${PROFILES_PATH}
    containerPath: /var/lib/kubelet/seccomp/profiles
    readOnly: true
- role: worker
  extraMounts:
  - hostPath: ${PROFILES_PATH}
    containerPath: /var/lib/kubelet/seccomp/profiles
    readOnly: true
EOF

log_info "Creating kind cluster '$CLUSTER_NAME' with 1 control-plane + 2 workers..."
log_info "Using profiles path: $PROFILES_PATH"
kind create cluster --config=$LAB_DIR/kind-config.yaml --name "$CLUSTER_NAME"

log_success "Kind cluster created successfully"

# Verify cluster is ready
log_info "Waiting for cluster to be ready..."
kubectl wait --for=condition=ready node --all --timeout=60s

if [[ "$STOP_AFTER_CLUSTER" == "true" ]]; then
    log_success "Cluster created successfully!"
    echo
    log_info "=== Manual Experimentation Mode ==="
    echo "The cluster is ready for manual testing:"
    echo "  Cluster name: $CLUSTER_NAME"
    echo "  Lab directory: $LAB_DIR"
    echo "  Profiles path: $PROFILES_PATH"
    echo "  kubectl get nodes"
    echo ""
    echo "Check profiles on all nodes:"
    ALL_NODES=$(docker ps --format "{{.Names}}" | grep "${CLUSTER_NAME}-")
    for NODE in $ALL_NODES; do
        echo "  docker exec $NODE ls /var/lib/kubelet/seccomp/profiles/"
    done
    echo ""
    echo "To cleanup later: kind delete cluster --name $CLUSTER_NAME"
    exit 0
fi


# Step 3: Verify seccomp profiles are loaded on all nodes
log_info "Step 3: Verifying seccomp profiles are available on all nodes"

# Get all nodes in the cluster
ALL_NODES=$(docker ps --format "{{.Names}}" | grep "${CLUSTER_NAME}-")

if [ -n "$ALL_NODES" ]; then
    for NODE in $ALL_NODES; do
        log_info "Checking seccomp profiles on node: $NODE"
        if docker exec $NODE ls /var/lib/kubelet/seccomp/profiles/ >/dev/null 2>&1; then
            docker exec $NODE ls -la /var/lib/kubelet/seccomp/profiles/
            log_success "Seccomp profiles are available on $NODE"
        else
            log_error "Seccomp profiles not found on $NODE"
        fi
        echo
    done
else
    log_error "Could not find cluster nodes"
fi

# Step 4: Test RuntimeDefault profile
log_info "Step 4: Testing RuntimeDefault seccomp profile"

log_info "Command: curl -L -o $LAB_DIR/pod-default.yaml $PODS_BASE_URL/default-pod.yaml"
if curl -L -o "$LAB_DIR/pod-default.yaml" "$PODS_BASE_URL/default-pod.yaml"; then
    log_success "Downloaded default-pod.yaml from official examples"
else
    log_error "Failed to download default-pod.yaml"
    exit 1
fi

log_info "Creating pod with RuntimeDefault seccomp profile..."
log_info "Command: kubectl apply -f $LAB_DIR/pod-default.yaml"
kubectl apply -f $LAB_DIR/pod-default.yaml

log_info "Waiting for pod to be ready..."
log_info "Command: kubectl wait --for=condition=ready pod/default-pod --timeout=30s"
kubectl wait --for=condition=ready pod/default-pod --timeout=30s

log_info "Pod status:"
log_info "Command: kubectl get pod default-pod -o wide"
kubectl get pod default-pod -o wide

# Step 5: Test audit profile
log_info "Step 5: Testing audit seccomp profile (logs all syscalls)"

log_info "Command: curl -L -o $LAB_DIR/pod-audit.yaml $PODS_BASE_URL/audit-pod.yaml"
if curl -L -o "$LAB_DIR/pod-audit.yaml" "$PODS_BASE_URL/audit-pod.yaml"; then
    log_success "Downloaded audit-pod.yaml from official examples"
else
    log_error "Failed to download audit-pod.yaml"
    exit 1
fi

log_info "Creating pod with audit seccomp profile..."
log_info "Command: kubectl apply -f $LAB_DIR/pod-audit.yaml"
kubectl apply -f $LAB_DIR/pod-audit.yaml

log_info "Waiting for pod to be ready..."
log_info "Command: kubectl wait --for=condition=ready pod/audit-pod --timeout=30s"
kubectl wait --for=condition=ready pod/audit-pod --timeout=30s

log_info "Checking audit logs for syscall activity:"
# Find which node the pod is running on
NODE=$(kubectl get pod audit-pod -o jsonpath='{.spec.nodeName}')
if [ -n "$NODE" ]; then
    log_info "Pod is running on node: $NODE"
    log_info "Command: docker exec $NODE journalctl --since '1 minute ago' | grep -i seccomp"

    # Check for seccomp audit logs on the correct node
    if docker exec $NODE journalctl --since '1 minute ago' | grep -i seccomp | tail -5; then
        log_success "Found seccomp audit logs"
    else
        log_info "No seccomp-specific audit logs found, checking general kernel logs"
        log_info "Command: docker exec $NODE dmesg | grep -i seccomp | tail -3"
        docker exec $NODE dmesg | grep -i seccomp | tail -3 || log_info "No seccomp messages in kernel logs"
    fi
else
    log_error "Could not determine pod node"
fi

log_info "Generating some syscall activity..."
log_info "Command: kubectl get pod audit-pod -o wide"
kubectl get pod audit-pod -o wide

log_info "Command: kubectl logs audit-pod"
kubectl logs audit-pod 2>/dev/null || log_info "No logs available yet"

log_success "Audit profile logs all syscalls (see commands above for detailed log investigation)"

log_info "Creating service for audit pod:"
log_info "Command: kubectl expose pod audit-pod --type=NodePort --port=5678"
kubectl expose pod audit-pod --type=NodePort --port=5678

log_info "Testing audit pod service:"
AUDIT_NODE_PORT=$(kubectl get service audit-pod -o jsonpath='{.spec.ports[0].nodePort}')
# Get worker node IP using kubectl
WORKER_IP=$(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
if [ -z "$WORKER_IP" ]; then
    WORKER_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
fi
log_info "Command: curl -s http://$WORKER_IP:$AUDIT_NODE_PORT/"

while  ! curl -s http://$WORKER_IP:$AUDIT_NODE_PORT/ >/dev/null 2>&1; do
    log_info "Waiting for audit pod service to be available..."
    sleep 3
done

log_warning "Checking for audit logs generated by service access on host because kind use host kernel"
if cat /var/log/syslog | grep -i http-echo ; then
    log_info "Found relevant audit logs in syslog"
else
    log_error "No relevant audit logs found in syslog"
    exit 1
fi

# Step 6: Test violation profile (blocks all syscalls)
log_info "Step 6: Testing violation seccomp profile (blocks all syscalls)"

log_info "Command: curl -L -o $LAB_DIR/pod-violation.yaml $PODS_BASE_URL/violation-pod.yaml"
if curl -L -o "$LAB_DIR/pod-violation.yaml" "$PODS_BASE_URL/violation-pod.yaml"; then
    log_success "Downloaded violation-pod.yaml from official examples"
else
    log_error "Failed to download violation-pod.yaml"
    exit 1
fi

log_info "Creating pod with violation seccomp profile (this should fail)..."
log_info "Command: kubectl apply -f $LAB_DIR/pod-violation.yaml"
kubectl apply -f $LAB_DIR/pod-violation.yaml

sleep 5

log_info "Checking pod status (should show creation issues):"
log_info "Command: kubectl get pod violation-pod"
kubectl get pod violation-pod
log_info "Command: kubectl describe pod violation-pod | tail -10"
kubectl describe pod violation-pod | tail -10

log_warning "This pod fails because the violation profile blocks all syscalls"

# Step 7: Test fine-grained profile
log_info "Step 7: Testing fine-grained seccomp profile (allows specific syscalls only)"

log_info "Command: curl -L -o $LAB_DIR/fine-pod.yaml $PODS_BASE_URL/fine-pod.yaml"
if curl -L -o "$LAB_DIR/fine-pod.yaml" "$PODS_BASE_URL/fine-pod.yaml"; then
    log_success "Downloaded fine-pod.yaml from official examples"
else
    log_error "Failed to download fine-pod.yaml"
    exit 1
fi

log_info "Creating pod with fine-grained seccomp profile..."
log_info "Command: kubectl apply -f $LAB_DIR/fine-pod.yaml"
kubectl apply -f $LAB_DIR/fine-pod.yaml

log_info "Waiting for pod to be ready..."
log_info "Command: kubectl wait --for=condition=ready pod/fine-pod --timeout=30s"
kubectl wait --for=condition=ready pod/fine-pod --timeout=30s

log_info "Checking pod status:"
log_info "Command: kubectl get pod fine-pod -o wide"
kubectl get pod fine-pod -o wide

log_info "Checking if fine-grained profile is working correctly..."
log_info "Command: kubectl logs fine-pod"
FINE_GRAINED_LOGS=$(kubectl logs fine-pod 2>&1)
echo "$FINE_GRAINED_LOGS"

log_info "Creating service for fine-grained pod:"
log_info "Command: kubectl expose pod fine-pod --type=NodePort --port=5678"
kubectl expose pod fine-pod --type=NodePort --port=5678

log_info "Testing fine-grained pod service and generating syscalls:"
FINE_NODE_PORT=$(kubectl get service fine-pod -o jsonpath='{.spec.ports[0].nodePort}')
# Get worker node IP using kubectl
WORKER_IP=$(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
log_info "Command: curl -s http://$WORKER_IP:$FINE_NODE_PORT/"

while ! curl -s http://$WORKER_IP:$FINE_NODE_PORT/ >/dev/null 2>&1; do
    log_info "Waiting for fine-grained pod service to be available..."
    sleep 3
done
log_success "Fine-grained seccomp profile is functioning correctly"


# Step 9: Summary and cleanup
log_info "Step 9: Summary and cleanup"

echo "=== Tutorial Summary ==="
echo "1. RuntimeDefault: Uses container runtime's default syscall filtering (~44 blocked syscalls)"
echo "2. Audit: Logs all syscalls but allows them (good for learning/debugging)"
echo "3. Violation: Blocks all syscalls (too restrictive for most apps)"
echo "4. Fine-grained: Custom allowlist of specific syscalls (production-ready approach)"
echo

log_info "Resources preserved. You can continue experimenting!"
echo "To clean up later, run:"
echo "  kind delete cluster --name $CLUSTER_NAME"
echo "  rm -rf $LAB_DIR"

