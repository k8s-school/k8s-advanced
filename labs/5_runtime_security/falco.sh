#!/bin/bash

# Falco Lab Automation Script
# This script automates the Falco runtime security lab

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
CLUSTER_NAME="${CLUSTER_NAME:-falco}"
NAMESPACE="falco"
TEST_TIMEOUT=300

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    for tool in kubectl helm ktbx; do
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
        log_info "Please ensure a cluster exists. Create one with: ktbx create -name ${CLUSTER_NAME}"
        exit 1
    fi

    local cluster_context=$(kubectl config current-context 2>/dev/null || echo "unknown")
    log_success "Connected to cluster: $cluster_context"
}

# Function to add Falco Helm repository
setup_helm_repo() {
    log_info "Setting up Falco Helm repository..."

    if ! helm repo list | grep -q falcosecurity; then
        helm repo add falcosecurity https://falcosecurity.github.io/charts
    fi

    helm repo update
    log_success "Falco Helm repository is ready"
}

# Function to install Falco
install_falco() {
    log_info "Installing Falco..."

    # Check if Falco is already installed
    if helm list -n "$NAMESPACE" | grep -q falco; then
        log_warning "Falco is already installed, upgrading..."
        helm upgrade falco falcosecurity/falco --namespace "$NAMESPACE" \
            --set tty=true \
            --set falcosidekick.enabled=true \
            --set falcosidekick.webui.enabled=true
    else
        # Create namespace if it doesn't exist
        kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

        helm install falco falcosecurity/falco --namespace "$NAMESPACE" \
            --set tty=true \
            --set falcosidekick.enabled=true \
            --set falcosidekick.webui.enabled=true
    fi

    log_info "Waiting for Falco pods to be ready..."
    kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout="${TEST_TIMEOUT}s"

    log_success "Falco installation completed"
}

# Function to verify Falco installation
verify_falco() {
    log_info "Verifying Falco installation..."

    # Check pods are running
    local falco_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l)
    if [ "$falco_pods" -eq 0 ]; then
        log_error "No Falco pods found"
        return 1
    fi

    # Check logs
    log_info "Checking Falco logs..."
    kubectl logs -l app.kubernetes.io/name=falco -n "$NAMESPACE" -c falco --tail=5 | head -n 3

    log_success "Falco is running correctly"
}

# Function to create test workload
create_test_workload() {
    log_info "Creating test workload..."

    # Create test deployment
    kubectl create deployment test-app --image=nginx:alpine --dry-run=client -o yaml | kubectl apply -f -

    # Wait for pod to be ready
    kubectl wait --for=condition=Ready pod -l app=test-app --timeout=60s

    # Get pod name
    TEST_POD=$(kubectl get pods -l app=test-app -o jsonpath='{.items[0].metadata.name}')
    log_success "Test pod created: $TEST_POD"
}

# Function to test default Falco rules
test_default_rules() {
    log_info "Testing default Falco rules..."

    # Start log monitoring in background
    local log_file="/tmp/falco-test-logs-$$"
    kubectl logs -l app.kubernetes.io/name=falco -n "$NAMESPACE" -c falco -f > "$log_file" 2>&1 &
    local log_pid=$!

    # Give logs a moment to start
    sleep 2

    log_info "1. Testing 'Read sensitive file untrusted' rule..."
    kubectl exec "$TEST_POD" -- cat /etc/shadow || echo "Expected to fail"
    sleep 2

    log_info "2. Testing 'Shell in container' rule..."
    kubectl exec "$TEST_POD" -- /bin/sh -c "whoami"
    sleep 2

    log_info "3. Testing 'Executing binary not part of base image' rule..."
    kubectl exec "$TEST_POD" -- chmod +s /bin/ls || echo "Expected to fail"
    sleep 2

    # Stop log monitoring
    kill $log_pid 2>/dev/null || true
    wait $log_pid 2>/dev/null || true

    # Check for alerts
    log_info "Checking for security alerts..."
    if grep -q -E "(Warning|Notice|Error|Critical)" "$log_file" 2>/dev/null; then
        log_success "Security alerts detected!"
        grep -E "(Warning|Notice|Error|Critical)" "$log_file" | tail -3
    else
        log_warning "No security alerts found in logs"
    fi

    rm -f "$log_file"
}

# Function to create custom CKS rules
create_custom_rules() {
    log_info "Creating custom CKS rules..."

    cat > falco-cks-values.yaml << 'EOF'
# Configuration for Falco CKS Lab
customRules:
  cks_rules.yaml: |-
    # 1. Rule for Network Tools
    - rule: CKS Network Tool Usage
      desc: Detect network reconnaissance tools
      # Simple and robust condition for lab environments
      condition: >
        evt.type = execve and
        (proc.name in (nmap, netcat, nc, telnet, wget, curl))
      output: "ALERT_CKS: Network tool detected (user=%user.name pod=%k8s.pod.name tool=%proc.name cmdline=%proc.cmdline)"
      priority: WARNING
      tags: [network, reconnaissance]

    # 2. Rule for Privilege Escalation
    - rule: CKS Privilege Escalation Attempt
      desc: Detect potential privilege escalation
      # Note: 'passwd' is used here for testing even if run by root
      condition: >
        evt.type = execve and
        (proc.name in (sudo, su, passwd))
      output: "ALERT_CKS: Privilege escalation tool (user=%user.name pod=%k8s.pod.name proc=%proc.name)"
      priority: CRITICAL
      tags: [privilege_escalation]
EOF

    # Apply custom rules
    helm upgrade falco falcosecurity/falco --namespace "$NAMESPACE" \
        --set tty=true \
        --set falcosidekick.enabled=true \
        --set falcosidekick.webui.enabled=true \
        -f falco-cks-values.yaml

    # Wait for falco to restart
    kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout="${TEST_TIMEOUT}s"

    log_success "Custom CKS rules applied"
}

# Function to test custom rules
test_custom_rules() {
    log_info "Testing custom CKS rules..."

    # Create attack pod
    kubectl run test-attack --image=nginx:alpine --overrides='{"apiVersion":"v1","kind":"Pod","spec":{"containers":[{"name":"test-attack","image":"nginx:alpine","command":["sleep","3600"]}]}}' || true
    kubectl wait --for=condition=Ready pod test-attack --timeout=60s

    # Start log monitoring
    local log_file="/tmp/falco-custom-logs-$$"
    kubectl logs -l app.kubernetes.io/name=falco -n "$NAMESPACE" -c falco -f | grep -v "k8s_pod_name=<NA>" > "$log_file" 2>&1 &
    local log_pid=$!

    sleep 2

    log_info "1. Testing network detection rule..."
    kubectl exec test-attack -- curl google.com || echo "Expected network call"
    sleep 3

    log_info "2. Testing privilege escalation rule..."
    kubectl exec test-attack -- passwd || echo "Expected passwd command"
    sleep 3

    # Stop log monitoring
    kill $log_pid 2>/dev/null || true
    wait $log_pid 2>/dev/null || true

    # Check for custom alerts
    log_info "Checking for custom alerts..."
    if grep -q "ALERT_CKS" "$log_file" 2>/dev/null; then
        log_success "Custom CKS alerts detected!"
        grep "ALERT_CKS" "$log_file" | tail -2
    else
        log_warning "No custom CKS alerts found"
        # Show recent logs for debugging
        log_info "Recent Falco logs:"
        kubectl logs -l app.kubernetes.io/name=falco -n "$NAMESPACE" -c falco --tail=10
    fi

    rm -f "$log_file"
}

# Function to test modified shell rule
test_modified_shell_rule() {
    log_info "Testing modified shell rule..."

    # Add modified shell rule to existing config
    cat >> falco-cks-values.yaml << 'EOF'
    - rule: Terminal shell in container
      desc: A shell was spawned in a container with an attached terminal
      condition: >
        spawned_process and container
        and shell_procs and proc.tty != 0
        and container.id != host
        and k8s.pod.name != "<NA>"
      output: "[CKS_UPDATE] Shell detected! pod=%k8s.pod.name image=%container.image.repository tty=%proc.tty"
      priority: WARNING
EOF

    # Apply the changes
    helm upgrade falco falcosecurity/falco --namespace "$NAMESPACE" \
        --set tty=true \
        --set falcosidekick.enabled=true \
        --set falcosidekick.webui.enabled=true \
        -f falco-cks-values.yaml

    # Wait for falco to restart
    kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout="${TEST_TIMEOUT}s"

    # Start log monitoring
    local log_file="/tmp/falco-shell-logs-$$"
    kubectl logs -l app.kubernetes.io/name=falco -n "$NAMESPACE" -c falco -f > "$log_file" 2>&1 &
    local log_pid=$!

    sleep 2

    log_info "Testing modified shell rule..."
    # This should trigger the modified shell rule
    timeout 10 kubectl exec -it test-attack -- sh -c "echo 'test shell access'" || true
    sleep 3

    # Stop log monitoring
    kill $log_pid 2>/dev/null || true
    wait $log_pid 2>/dev/null || true

    # Check for modified shell alerts
    log_info "Checking for modified shell alerts..."
    if grep -q "CKS_UPDATE.*Shell detected" "$log_file" 2>/dev/null; then
        log_success "Modified shell rule alert detected!"
        grep "CKS_UPDATE.*Shell detected" "$log_file" | tail -1
    else
        log_warning "No modified shell rule alerts found"
    fi

    rm -f "$log_file"
}

# Function to run diagnostics
run_diagnostics() {
    log_info "Running diagnostics..."

    echo "=== Falco Pods Status ==="
    kubectl get pods -n "$NAMESPACE"

    echo -e "\n=== Falco ConfigMap ==="
    kubectl get configmap -n "$NAMESPACE" | grep falco || echo "No Falco ConfigMaps found"

    echo -e "\n=== Recent Falco Events ==="
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -5

    echo -e "\n=== Falco Service ==="
    kubectl get svc -n "$NAMESPACE"

    # Test rule validation
    echo -e "\n=== Rule Validation ==="
    local falco_pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=falco -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$falco_pod" ]; then
        echo "Loaded rule files:"
        kubectl exec "$falco_pod" -n "$NAMESPACE" -c falco -- ls -la /etc/falco/*.yaml /etc/falco/rules.d/*.yaml 2>/dev/null || echo "No additional rules found"

        # Validate rules (check if custom file exists first)
        kubectl exec "$falco_pod" -n "$NAMESPACE" -c falco -- bash -c '
        if [ -f /etc/falco/falco_rules.local.yaml ]; then
          falco --validate /etc/falco/falco_rules.local.yaml
        else
          echo "Custom rules file not found, checking default rules"
          falco --validate /etc/falco/falco_rules.yaml
        fi'

        # List all compiled rules (uses default config which loads all rule files)
        echo "All loaded rules:"
        kubectl exec "$falco_pod" -n "$NAMESPACE" -c falco -- falco --list | head -20
    fi
}

# Function to cleanup resources
cleanup() {
    log_info "Cleaning up test resources..."

    kubectl delete pod test-attack --ignore-not-found=true
    kubectl delete deployment test-app --ignore-not-found=true
    rm -f falco-cks-values.yaml

    log_success "Cleanup completed"
}

# Function to show Falco UI access instructions
show_ui_access() {
    log_info "Falco UI access instructions:"
    echo -e "${YELLOW}To access Falco UI, run:${NC}"
    echo "kubectl port-forward svc/falco-falcosidekick-ui 2802:2802 -n falco"
    echo "Then open: http://localhost:2802"
}

# Main execution function
main() {
    log_info "Starting Falco Lab automation..."

    check_prerequisites
    verify_cluster
    setup_helm_repo
    install_falco
    verify_falco
    create_test_workload
    test_default_rules
    create_custom_rules
    test_custom_rules
    test_modified_shell_rule
    run_diagnostics
    show_ui_access

    log_success "Falco Lab automation completed successfully!"

    # Ask user if they want to cleanup
    echo -e "\n${YELLOW}Do you want to cleanup test resources? (y/n):${NC}"
    read -r cleanup_choice
    if [[ "$cleanup_choice" =~ ^[Yy]$ ]]; then
        cleanup
    fi
}

# Trap to ensure cleanup on script exit
trap 'log_warning "Script interrupted, cleaning up..."; cleanup; exit 1' INT TERM

# Run main function
main "$@"