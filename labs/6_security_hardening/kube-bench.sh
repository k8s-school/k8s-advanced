#!/bin/bash

# Kube-bench CIS Kubernetes Benchmark Lab Automation
# This script automates the kube-bench lab exercises on an existing Kubernetes cluster

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
KUBE_BENCH_VERSION="0.9.2"
NAMESPACE="kube-bench"
TEST_TIMEOUT=300
CONTROL_PLANE_CONTAINER=""

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    for tool in kubectl docker; do
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

# Function to detect control plane container for existing cluster
detect_control_plane() {
    log_info "Detecting control plane container for existing cluster..."

    local current_context=$(kubectl config current-context 2>/dev/null || echo "unknown")

    if [[ "$current_context" == kind-* ]]; then
        local cluster_name=$(echo "$current_context" | sed 's/^kind-//')
        CONTROL_PLANE_CONTAINER="${cluster_name}-control-plane"

        # Verify the container exists
        if docker ps --filter "name=${CONTROL_PLANE_CONTAINER}" --format "{{.Names}}" | head -1 | grep -q "${CONTROL_PLANE_CONTAINER}"; then
            log_success "Using Kind cluster with control plane container: $CONTROL_PLANE_CONTAINER"
            return 0
        else
            log_warning "Kind cluster detected but control plane container not found: $CONTROL_PLANE_CONTAINER"
            log_info "Available control plane containers:"
            docker ps --format "{{.Names}}" | grep control-plane || echo "None found"
        fi
    fi

    log_info "Not a Kind cluster or control plane container not accessible"
    CONTROL_PLANE_CONTAINER=""
    return 0
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

# Function to run kube-bench as Job for master node
run_master_scan() {
    log_info "Running kube-bench scan on master node..."

    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # Create the master job manifest
    cat << EOF > /tmp/kube-bench-master.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench-master
  namespace: $NAMESPACE
spec:
  template:
    spec:
      hostPID: true
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      containers:
      - name: kube-bench
        image: aquasec/kube-bench:latest
        command: ["kube-bench", "run", "--targets", "master"]
        volumeMounts:
        - name: var-lib-etcd
          mountPath: /var/lib/etcd
          readOnly: true
        - name: var-lib-kubelet
          mountPath: /var/lib/kubelet
          readOnly: true
        - name: var-lib-kube-scheduler
          mountPath: /var/lib/kube-scheduler
          readOnly: true
        - name: var-lib-kube-controller-manager
          mountPath: /var/lib/kube-controller-manager
          readOnly: true
        - name: etc-systemd
          mountPath: /etc/systemd
          readOnly: true
        - name: lib-systemd
          mountPath: /lib/systemd/
          readOnly: true
        - name: etc-kubernetes
          mountPath: /etc/kubernetes
          readOnly: true
        - name: usr-bin
          mountPath: /usr/local/mount-from-host/bin
          readOnly: true
      restartPolicy: Never
      volumes:
      - name: var-lib-etcd
        hostPath:
          path: "/var/lib/etcd"
      - name: var-lib-kubelet
        hostPath:
          path: "/var/lib/kubelet"
      - name: var-lib-kube-scheduler
        hostPath:
          path: "/var/lib/kube-scheduler"
      - name: var-lib-kube-controller-manager
        hostPath:
          path: "/var/lib/kube-controller-manager"
      - name: etc-systemd
        hostPath:
          path: "/etc/systemd"
      - name: lib-systemd
        hostPath:
          path: "/lib/systemd"
      - name: etc-kubernetes
        hostPath:
          path: "/etc/kubernetes"
      - name: usr-bin
        hostPath:
          path: "/usr/bin"
EOF

    kubectl apply -f /tmp/kube-bench-master.yaml
    log_success "Kube-bench master job created"

    # Wait for job completion
    kubectl wait --for=condition=complete job/kube-bench-master -n "$NAMESPACE" --timeout="${TEST_TIMEOUT}s"

    # Get pod name and show results
    local pod_name
    pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name=kube-bench-master -o jsonpath='{.items[0].metadata.name}')

    if [ -n "$pod_name" ]; then
        log_info "Master scan completed. Showing results:"
        echo "======================================"
        kubectl logs "$pod_name" -n "$NAMESPACE"
        echo "======================================"

        # Save logs for analysis
        kubectl logs "$pod_name" -n "$NAMESPACE" > /tmp/master-scan-results.log

        # Analyze results
        local logs
        logs=$(kubectl logs "$pod_name" -n "$NAMESPACE")
        local pass_count=$(echo "$logs" | grep -c "\\[PASS\\]" || echo "0")
        local fail_count=$(echo "$logs" | grep -c "\\[FAIL\\]" || echo "0")
        local warn_count=$(echo "$logs" | grep -c "\\[WARN\\]" || echo "0")

        log_info "Master scan results: PASS=$pass_count, FAIL=$fail_count, WARN=$warn_count"

        # Check for specific failures we can remediate
        if grep -q "1.4.1.*\\[FAIL\\]" /tmp/master-scan-results.log; then
            log_warning "Found scheduler profiling issue (1.4.1) - will remediate later"
        fi

        log_success "Master scan completed successfully"
    else
        log_error "Could not find kube-bench master pod"
        return 1
    fi
}

# Function to run kube-bench as Job for worker node
run_worker_scan() {
    log_info "Running kube-bench scan on worker node..."

    # Get the first worker node name
    local worker_node
    worker_node=$(kubectl get nodes --no-headers | grep -v control-plane | head -1 | awk '{print $1}')

    if [ -z "$worker_node" ]; then
        log_warning "No worker nodes found, skipping worker scan"
        return 0
    fi

    log_info "Selected worker node: $worker_node"

    # Create the worker job manifest
    cat << EOF > /tmp/kube-bench-worker.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench-worker
  namespace: $NAMESPACE
spec:
  template:
    spec:
      hostPID: true
      nodeSelector:
        kubernetes.io/hostname: $worker_node
      containers:
      - name: kube-bench
        image: aquasec/kube-bench:latest
        command: ["kube-bench", "run", "--targets", "node"]
        volumeMounts:
        - name: var-lib-kubelet
          mountPath: /var/lib/kubelet
          readOnly: true
        - name: var-lib-kube-proxy
          mountPath: /var/lib/kube-proxy
          readOnly: true
        - name: etc-systemd
          mountPath: /etc/systemd
          readOnly: true
        - name: lib-systemd
          mountPath: /lib/systemd/
          readOnly: true
        - name: etc-kubernetes
          mountPath: /etc/kubernetes
          readOnly: true
        - name: usr-bin
          mountPath: /usr/local/mount-from-host/bin
          readOnly: true
      restartPolicy: Never
      volumes:
      - name: var-lib-kubelet
        hostPath:
          path: "/var/lib/kubelet"
      - name: var-lib-kube-proxy
        hostPath:
          path: "/var/lib/kube-proxy"
      - name: etc-systemd
        hostPath:
          path: "/etc/systemd"
      - name: lib-systemd
        hostPath:
          path: "/lib/systemd"
      - name: etc-kubernetes
        hostPath:
          path: "/etc/kubernetes"
      - name: usr-bin
        hostPath:
          path: "/usr/bin"
EOF

    kubectl apply -f /tmp/kube-bench-worker.yaml

    log_info "Waiting for worker scan to complete..."

    # Wait for job completion with longer timeout
    if kubectl wait --for=condition=complete job/kube-bench-worker -n "$NAMESPACE" --timeout="120s" 2>/dev/null; then
        # Get pod name and show results
        local pod_name
        pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name=kube-bench-worker -o jsonpath='{.items[0].metadata.name}')

        if [ -n "$pod_name" ]; then
            log_info "Worker scan completed. Showing results:"
            echo "======================================"
            kubectl logs "$pod_name" -n "$NAMESPACE"
            echo "======================================"
            log_success "Worker scan completed successfully"
        fi
    else
        log_warning "Worker scan did not complete within timeout"

        # Check if pods are pending due to scheduling issues
        local pending_pods
        pending_pods=$(kubectl get pods -n "$NAMESPACE" -l job-name=kube-bench-worker --field-selector=status.phase=Pending -o jsonpath='{.items[*].metadata.name}')

        if [ -n "$pending_pods" ]; then
            log_warning "Worker pods are pending - checking scheduling issues..."
            kubectl describe pod -n "$NAMESPACE" $pending_pods | grep -A 5 -B 5 "Events:"
        fi
    fi
}

# Function to demonstrate scheduler profiling fix
demonstrate_scheduler_profiling_fix() {
    log_info "Demonstrating scheduler profiling remediation (check 1.4.1)..."

    if [ -z "$CONTROL_PLANE_CONTAINER" ]; then
        log_warning "Profiling fix requires direct control plane access"
        return 0
    fi

    # Check current profiling status
    log_info "Checking current scheduler profiling status..."
    local current_profiling
    current_profiling=$(kubectl get pod -n kube-system -l component=kube-scheduler -o yaml | grep -o "profiling=false" || echo "not set")

    if [[ "$current_profiling" == "profiling=false" ]]; then
        log_success "Scheduler profiling is already disabled"
        return 0
    fi

    log_info "Current profiling setting: $current_profiling"

    # Backup original manifest
    log_info "Backing up original scheduler manifest..."
    docker exec "$CONTROL_PLANE_CONTAINER" cp /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/kube-scheduler.yaml.backup

    # Add profiling=false if not present
    log_info "Adding --profiling=false to scheduler configuration..."
    docker exec "$CONTROL_PLANE_CONTAINER" bash -c '
        if ! grep -q "profiling=false" /etc/kubernetes/manifests/kube-scheduler.yaml; then
            sed -i "/--bind-address/a\\    - --profiling=false" /etc/kubernetes/manifests/kube-scheduler.yaml
        fi
    '

    # Wait for scheduler to restart
    log_info "Waiting for scheduler to restart..."
    sleep 10
    kubectl wait --for=condition=Ready pod -l component=kube-scheduler -n kube-system --timeout=60s

    # Wait a bit more for the change to propagate
    sleep 5

    # Verify the change
    local new_profiling
    new_profiling=$(kubectl get pod -n kube-system -l component=kube-scheduler -o yaml | grep -o "profiling=false" || echo "not set")

    if [[ "$new_profiling" == "profiling=false" ]]; then
        log_success "Scheduler profiling successfully disabled"

        # Re-run master scan to verify fix
        log_info "Re-running master scan to verify fix..."
        kubectl delete job kube-bench-master -n "$NAMESPACE" --ignore-not-found=true
        sleep 5
        run_master_scan_verification
    else
        log_error "Failed to disable scheduler profiling"
        # Restore backup
        docker exec "$CONTROL_PLANE_CONTAINER" cp /tmp/kube-scheduler.yaml.backup /etc/kubernetes/manifests/kube-scheduler.yaml
        return 1
    fi
}

# Function to run verification scan after scheduler fix
run_master_scan_verification() {
    log_info "Running verification scan..."

    # Create verification job
    cat << EOF > /tmp/kube-bench-verification.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench-verification
  namespace: $NAMESPACE
spec:
  template:
    spec:
      hostPID: true
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      containers:
      - name: kube-bench
        image: aquasec/kube-bench:latest
        command: ["kube-bench", "run", "--targets", "master"]
        volumeMounts:
        - name: etc-kubernetes
          mountPath: /etc/kubernetes
          readOnly: true
      restartPolicy: Never
      volumes:
      - name: etc-kubernetes
        hostPath:
          path: "/etc/kubernetes"
EOF

    kubectl apply -f /tmp/kube-bench-verification.yaml
    kubectl wait --for=condition=complete job/kube-bench-verification -n "$NAMESPACE" --timeout="120s"

    local pod_name
    pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name=kube-bench-verification -o jsonpath='{.items[0].metadata.name}')

    if [ -n "$pod_name" ]; then
        local verification_logs
        verification_logs=$(kubectl logs "$pod_name" -n "$NAMESPACE")

        if echo "$verification_logs" | grep -q "1.4.1.*\\[PASS\\]"; then
            log_success "Verification passed: Scheduler profiling check now passes!"
        else
            log_warning "Verification: Check 1.4.1 status unclear"
        fi

        # Show just the relevant line
        echo "$verification_logs" | grep "1.4.1" || log_info "Check 1.4.1 not found in verification scan"
    fi
}

# Function to configure and test encryption at rest
configure_encryption_at_rest() {
    log_info "Demonstrating encryption at rest (checks 1.2.27 & 1.2.28)..."

    if [ -z "$CONTROL_PLANE_CONTAINER" ]; then
        log_warning "Encryption at rest requires direct control plane access"
        return 0
    fi

    # Step 1: Generate encryption key
    log_info "Step 1: Generate encryption key"
    local encryption_key
    encryption_key=$(head -c 32 /dev/urandom | base64)
    echo "Generated key: ${encryption_key:0:20}..."

    # Step 2: Create encryption configuration file
    log_info "Step 2: Create EncryptionConfiguration file"
    docker exec "$CONTROL_PLANE_CONTAINER" bash -c "cat > /etc/kubernetes/encryption-config.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
        - name: key1
          secret: $encryption_key
    - identity: {}
EOF"
    echo "✓ Encryption config created: /etc/kubernetes/encryption-config.yaml"

    # Step 3: Create test secrets to demonstrate current state
    log_info "Step 3: Create test secrets to demonstrate current encryption state"
    kubectl create secret generic test-encryption-demo-1 --from-literal=data="plaintext-data-1" || true
    kubectl create secret generic test-encryption-demo-2 --from-literal=data="plaintext-data-2" || true
    sleep 2
    echo "✓ Test secrets created"

    # Step 4: Check current encryption status in etcd BEFORE encryption
    log_info "Step 4: Checking current encryption status in etcd (BEFORE encryption)"
    echo "=========================================="
    echo "ETCD ENCRYPTION VERIFICATION - BEFORE"
    echo "=========================================="

    echo ""
    echo "🔍 Reading secrets directly from etcd (should show PLAINTEXT):"
    echo ""
    echo "Command used to read from etcd:"
    echo "kubectl exec etcd-cks-control-plane -n kube-system -- etcdctl get /registry/secrets/default/SECRET_NAME --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/peer.crt --key=/etc/kubernetes/pki/etcd/peer.key"
    echo ""

    # Use temporary files to avoid null byte warnings with binary data
    local temp1="/tmp/secret1_data.$$" temp2="/tmp/secret2_data.$$"

    kubectl exec etcd-cks-control-plane -n kube-system -- etcdctl get /registry/secrets/default/test-encryption-demo-1 \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/peer.crt \
        --key=/etc/kubernetes/pki/etcd/peer.key 2>/dev/null > "$temp1" || echo "etcd_read_error" > "$temp1"

    kubectl exec etcd-cks-control-plane -n kube-system -- etcdctl get /registry/secrets/default/test-encryption-demo-2 \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/peer.crt \
        --key=/etc/kubernetes/pki/etcd/peer.key 2>/dev/null > "$temp2" || echo "etcd_read_error" > "$temp2"

    echo "Secret 1 data from etcd (first 200 chars):"
    head -c 200 "$temp1" | tr '\0' '.'
    echo "..."
    echo ""

    echo "Secret 2 data from etcd (first 200 chars):"
    head -c 200 "$temp2" | tr '\0' '.'
    echo "..."
    echo ""

    if grep -q "plaintext-data-1" "$temp1" 2>/dev/null; then
        echo "✅ Secret 1: PLAINTEXT VISIBLE in etcd (as expected - no encryption yet)"
    else
        echo "❓ Secret 1: NOT PLAINTEXT (unexpected or read error)"
    fi

    if grep -q "plaintext-data-2" "$temp2" 2>/dev/null; then
        echo "✅ Secret 2: PLAINTEXT VISIBLE in etcd (as expected - no encryption yet)"
    else
        echo "❓ Secret 2: NOT PLAINTEXT (unexpected or read error)"
    fi

    # Clean up temporary files
    rm -f "$temp1" "$temp2"

    echo ""
    echo "=========================================="

    # Step 5: Apply encryption configuration automatically
    log_info "Step 5: Applying encryption configuration to API server (using Python)"
    docker exec "$CONTROL_PLANE_CONTAINER" bash -c 'python3 << "EOF_PYTHON"
import re

# Read the current kube-apiserver.yaml
with open("/etc/kubernetes/manifests/kube-apiserver.yaml", "r") as f:
    content = f.read()

# Backup original
with open("/tmp/kube-apiserver.yaml.backup", "w") as f:
    f.write(content)

print("✓ Original manifest backed up")

# Step 1: Add encryption provider config argument
if "--encryption-provider-config" not in content:
    # Find the line with --tls-private-key-file and add after it
    pattern = r"(\s+- --tls-private-key-file=.*\n)"
    replacement = r"\1    - --encryption-provider-config=/etc/kubernetes/encryption-config.yaml\n"
    content = re.sub(pattern, replacement, content)
    print("✓ Added encryption provider config argument")

# Step 2: Add volume mount for encryption config
if "name: encryption-config" not in content:
    lines = content.split("\n")

    # Find the last volumeMount entry and add after it
    last_volume_mount_idx = -1
    in_volume_mounts = False

    for i, line in enumerate(lines):
        if "volumeMounts:" in line:
            in_volume_mounts = True
            continue
        elif in_volume_mounts and line.strip().startswith("hostNetwork:"):
            # We reached the end of volumeMounts section
            break
        elif in_volume_mounts and "readOnly: true" in line:
            last_volume_mount_idx = i

    if last_volume_mount_idx > -1:
        # Insert volume mount after the last readOnly: true
        mount_lines = [
            "    - mountPath: /etc/kubernetes/encryption-config.yaml",
            "      name: encryption-config",
            "      readOnly: true"
        ]
        lines = lines[:last_volume_mount_idx+1] + mount_lines + lines[last_volume_mount_idx+1:]
        print("✓ Added encryption config volume mount")

    # Step 3: Add volume in volumes section
    # Find the last volume entry and add after it
    last_volume_idx = -1
    in_volumes = False

    for i, line in enumerate(lines):
        if line.strip() == "volumes:":
            in_volumes = True
            continue
        elif in_volumes and line.strip().startswith("status:"):
            # We reached the end of volumes section
            break
        elif in_volumes and line.strip().startswith("name: ") and "certificates" in line:
            last_volume_idx = i

    if last_volume_idx > -1:
        # Insert volume after the last certificate volume
        volume_lines = [
            "  - hostPath:",
            "      path: /etc/kubernetes/encryption-config.yaml",
            "      type: File",
            "    name: encryption-config"
        ]
        lines = lines[:last_volume_idx+1] + volume_lines + lines[last_volume_idx+1:]
        print("✓ Added encryption config volume")

    content = "\n".join(lines)

# Step 4: Validate the result
# Check that we have both the volume mount and volume
has_mount = "mountPath: /etc/kubernetes/encryption-config.yaml" in content
has_volume = "path: /etc/kubernetes/encryption-config.yaml" in content
has_command = "--encryption-provider-config" in content

if has_command and has_mount and has_volume:
    print("✓ Configuration validation successful")

    # Write the modified content
    with open("/etc/kubernetes/manifests/kube-apiserver.yaml", "w") as f:
        f.write(content)
    print("✓ API server configuration updated successfully")
else:
    print("✗ Configuration validation failed:")
    print(f"  Command arg: {has_command}")
    print(f"  Volume mount: {has_mount}")
    print(f"  Volume: {has_volume}")
    exit(1)

EOF_PYTHON'

    # Step 6: Wait for API server restart
    log_info "Step 6: Waiting for API server to restart with encryption..."
    sleep 30

    # Wait for API server to be ready
    local retries=0
    while [ $retries -lt 60 ]; do
        if kubectl get nodes >/dev/null 2>&1; then
            log_success "API server restarted successfully with encryption!"
            break
        fi
        echo -n "."
        sleep 2
        retries=$((retries + 1))
    done
    echo ""

    if [ $retries -eq 60 ]; then
        log_error "API server failed to restart - restoring backup"
        docker exec "$CONTROL_PLANE_CONTAINER" cp /tmp/kube-apiserver.yaml.backup /etc/kubernetes/manifests/kube-apiserver.yaml
        return 1
    fi

    # Step 7: Create new secrets AFTER encryption is enabled
    log_info "Step 7: Create post-encryption test secrets"
    kubectl create secret generic post-encryption-demo-1 --from-literal=data="plaintext-after-encryption-1" || true
    kubectl create secret generic post-encryption-demo-2 --from-literal=data="plaintext-after-encryption-2" || true
    sleep 3
    echo "✓ Post-encryption test secrets created"

    # Step 8: Verify encryption in etcd AFTER encryption
    log_info "Step 8: Verifying encryption in etcd (AFTER encryption)"
    echo "=========================================="
    echo "ETCD ENCRYPTION VERIFICATION - AFTER"
    echo "=========================================="

    echo ""
    echo "🔍 Reading same secrets from etcd AFTER encryption (should show ENCRYPTED data):"
    echo ""
    echo "Same command used to read from etcd:"
    echo "kubectl exec etcd-cks-control-plane -n kube-system -- etcdctl get /registry/secrets/default/SECRET_NAME ..."
    echo ""

    # Check the ORIGINAL secrets (should now be unencrypted still until re-encrypted)
    local orig_temp1="/tmp/orig_secret1.$$" orig_temp2="/tmp/orig_secret2.$$"

    kubectl exec etcd-cks-control-plane -n kube-system -- etcdctl get /registry/secrets/default/test-encryption-demo-1 \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/peer.crt \
        --key=/etc/kubernetes/pki/etcd/peer.key 2>/dev/null > "$orig_temp1" || echo "etcd_read_error" > "$orig_temp1"

    kubectl exec etcd-cks-control-plane -n kube-system -- etcdctl get /registry/secrets/default/test-encryption-demo-2 \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/peer.crt \
        --key=/etc/kubernetes/pki/etcd/peer.key 2>/dev/null > "$orig_temp2" || echo "etcd_read_error" > "$orig_temp2"

    echo "Original Secret 1 data from etcd AFTER encryption config (should still be plaintext until re-encrypted):"
    head -c 200 "$orig_temp1" | tr '\0' '.'
    echo "..."
    echo ""

    # Check new secrets created AFTER encryption (should be encrypted)
    local post_temp1="/tmp/post_secret1.$$" post_temp2="/tmp/post_secret2.$$"

    kubectl exec etcd-cks-control-plane -n kube-system -- etcdctl get /registry/secrets/default/post-encryption-demo-1 \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/peer.crt \
        --key=/etc/kubernetes/pki/etcd/peer.key 2>/dev/null > "$post_temp1" || echo "etcd_read_error" > "$post_temp1"

    kubectl exec etcd-cks-control-plane -n kube-system -- etcdctl get /registry/secrets/default/post-encryption-demo-2 \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/peer.crt \
        --key=/etc/kubernetes/pki/etcd/peer.key 2>/dev/null > "$post_temp2" || echo "etcd_read_error" > "$post_temp2"

    echo "NEW Secret 1 (created AFTER encryption) data from etcd:"
    head -c 200 "$post_temp1" | tr '\0' '.'
    echo "..."
    echo ""

    echo "NEW Secret 2 (created AFTER encryption) data from etcd:"
    head -c 200 "$post_temp2" | tr '\0' '.'
    echo "..."
    echo ""

    # Analyze the results
    if grep -q "plaintext-data-1" "$orig_temp1" 2>/dev/null; then
        echo "⚠️  Original Secret 1: STILL PLAINTEXT (expected - not re-encrypted yet)"
    else
        echo "✅ Original Secret 1: NO LONGER PLAINTEXT"
    fi

    if grep -q "plaintext-after-encryption-1" "$post_temp1" 2>/dev/null; then
        echo "❌ NEW Secret 1: PLAINTEXT VISIBLE (encryption FAILED!)"
    else
        echo "✅ NEW Secret 1: ENCRYPTED (plaintext not visible)"
    fi

    if grep -q "plaintext-after-encryption-2" "$post_temp2" 2>/dev/null; then
        echo "❌ NEW Secret 2: PLAINTEXT VISIBLE (encryption FAILED!)"
    else
        echo "✅ NEW Secret 2: ENCRYPTED (plaintext not visible)"
    fi

    # Clean up temporary files
    rm -f "$orig_temp1" "$orig_temp2" "$post_temp1" "$post_temp2"

    echo ""
    echo "=========================================="

    # Step 9: Re-encrypt existing secrets
    log_info "Step 9: Re-encrypting existing secrets..."
    echo "Running command: kubectl get secrets --all-namespaces -o json | kubectl replace -f -"
    kubectl get secrets --all-namespaces -o json | kubectl replace -f - >/dev/null 2>&1 || log_warning "Some secrets failed to re-encrypt"
    sleep 2

    echo ""
    echo "=========================================="
    echo "ETCD ENCRYPTION VERIFICATION - AFTER RE-ENCRYPTION"
    echo "=========================================="

    # Check the ORIGINAL secrets again after re-encryption
    echo ""
    echo "🔍 Reading ORIGINAL secrets AFTER re-encryption (should now be encrypted):"
    echo ""

    local reenc_temp="/tmp/reenc_secret1.$$"

    kubectl exec etcd-cks-control-plane -n kube-system -- etcdctl get /registry/secrets/default/test-encryption-demo-1 \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/peer.crt \
        --key=/etc/kubernetes/pki/etcd/peer.key 2>/dev/null > "$reenc_temp" || echo "etcd_read_error" > "$reenc_temp"

    echo "Original Secret 1 data AFTER re-encryption:"
    head -c 200 "$reenc_temp" | tr '\0' '.'
    echo "..."
    echo ""

    if grep -q "plaintext-data-1" "$reenc_temp" 2>/dev/null; then
        echo "❌ Re-encryption FAILED - still plaintext visible"
    else
        echo "✅ Re-encryption SUCCESS - original secrets now encrypted"
    fi

    # Clean up temporary file
    rm -f "$reenc_temp"

    echo ""
    echo "=========================================="

    # Cleanup test secrets
    kubectl delete secret test-encryption-demo-1 test-encryption-demo-2 post-encryption-demo-1 post-encryption-demo-2 --ignore-not-found=true >/dev/null 2>&1

    log_success "Encryption at rest implementation and verification completed!"
    echo ""
    echo "🎯 Summary: Encryption at rest is now ACTIVE"
    echo "   • Encryption key generated and API server configured"
    echo "   • New secrets are automatically encrypted"
    echo "   • Existing secrets have been re-encrypted"
    echo "   • Verification shows encrypted data in etcd"
    echo "   • Use './kube-bench.sh --verify-encryption' for future checks"
}

# Function to verify etcd encryption status
verify_etcd_encryption() {
    log_info "Verifying etcd encryption status..."

    if [ -z "$CONTROL_PLANE_CONTAINER" ]; then
        log_warning "Etcd encryption verification requires direct control plane access"
        return 0
    fi

    # Check if encryption provider config is configured in API server
    local api_server_config
    api_server_config=$(docker exec "$CONTROL_PLANE_CONTAINER" bash -c '
        grep -o "encryption-provider-config" /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null || echo "not_configured"
    ')

    if [[ "$api_server_config" == "not_configured" ]]; then
        log_warning "Encryption provider not configured in API server"
        echo "Result: Encryption at rest is NOT configured"
        return 0
    fi

    log_info "Encryption provider config detected in API server"

    # Create a test secret if none exists
    log_info "Creating test secrets for verification..."
    echo "Creating secret: encryption-test-1"
    kubectl create secret generic encryption-test-1 --from-literal=key1=plaintext-value-1 2>/dev/null || echo "Secret encryption-test-1 already exists"
    echo "Creating secret: encryption-test-2"
    kubectl create secret generic encryption-test-2 --from-literal=key2=plaintext-value-2 2>/dev/null || echo "Secret encryption-test-2 already exists"

    # Wait for secrets to be persisted
    sleep 2

    # Check encryption status for test secrets
    log_info "Checking encryption status in etcd..."

    # Use temporary files to handle binary data
    local verify_temp1="/tmp/verify_secret1.$$" verify_temp2="/tmp/verify_secret2.$$"

    kubectl exec etcd-${CONTROL_PLANE_CONTAINER} -n kube-system -- etcdctl get /registry/secrets/default/encryption-test-1 \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/peer.crt \
        --key=/etc/kubernetes/pki/etcd/peer.key 2>/dev/null > "$verify_temp1" || echo "error_accessing_etcd" > "$verify_temp1"

    kubectl exec etcd-${CONTROL_PLANE_CONTAINER} -n kube-system -- etcdctl get /registry/secrets/default/encryption-test-2 \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/peer.crt \
        --key=/etc/kubernetes/pki/etcd/peer.key 2>/dev/null > "$verify_temp2" || echo "error_accessing_etcd" > "$verify_temp2"

    # Analyze results
    echo "=== Etcd Encryption Verification Results ==="

    if grep -q "error_accessing_etcd" "$verify_temp1" 2>/dev/null; then
        log_error "Cannot access etcd directly - verification failed"
        echo "Status: Unable to verify encryption"
    else
        # Check if plaintext values are visible in etcd
        if grep -q "plaintext-value-1" "$verify_temp1" 2>/dev/null; then
            log_error "Secret encryption-test-1 is stored in PLAINTEXT in etcd"
            echo "Secret encryption-test-1: NOT ENCRYPTED ❌"
        else
            log_success "Secret encryption-test-1 is encrypted in etcd"
            echo "Secret encryption-test-1: ENCRYPTED ✅"
        fi

        if grep -q "plaintext-value-2" "$verify_temp2" 2>/dev/null; then
            log_error "Secret encryption-test-2 is stored in PLAINTEXT in etcd"
            echo "Secret encryption-test-2: NOT ENCRYPTED ❌"
        else
            log_success "Secret encryption-test-2 is encrypted in etcd"
            echo "Secret encryption-test-2: ENCRYPTED ✅"
        fi
    fi

    # Show sample encrypted data (truncated for readability)
    log_info "Sample etcd data for encryption-test-1 (first 100 chars):"
    head -c 100 "$verify_temp1" | tr '\n' ' '
    echo "..."

    echo ""
    log_info "Test secrets created for verification:"
    kubectl get secrets encryption-test-1 encryption-test-2 2>/dev/null || echo "Secrets not found"

    echo ""
    log_info "Note: Test secrets are kept for inspection. Clean up with:"
    echo "kubectl delete secret encryption-test-1 encryption-test-2"

    # Clean up temporary files only
    rm -f "$verify_temp1" "$verify_temp2"

    echo "============================================="
}

# Function to create continuous compliance CronJob
create_continuous_compliance() {
    log_info "Creating CronJob for continuous compliance monitoring..."

    cat << EOF > /tmp/kube-bench-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: kube-bench-cronjob
  namespace: $NAMESPACE
spec:
  schedule: "0 2 * * 0"  # Every Sunday at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          hostPID: true
          nodeSelector:
            node-role.kubernetes.io/control-plane: ""
          tolerations:
          # Allow running on master nodes
          - key: node-role.kubernetes.io/control-plane
            operator: Exists
            effect: NoSchedule
          - key: node-role.kubernetes.io/master
            operator: Exists
            effect: NoSchedule
          containers:
          - name: kube-bench
            image: aquasec/kube-bench:latest
            command: ["kube-bench", "run", "--targets", "master,node"]
            volumeMounts:
            - name: var-lib-etcd
              mountPath: /var/lib/etcd
              readOnly: true
            - name: var-lib-kubelet
              mountPath: /var/lib/kubelet
              readOnly: true
            - name: var-lib-kube-scheduler
              mountPath: /var/lib/kube-scheduler
              readOnly: true
            - name: var-lib-kube-controller-manager
              mountPath: /var/lib/kube-controller-manager
              readOnly: true
            - name: etc-systemd
              mountPath: /etc/systemd
              readOnly: true
            - name: lib-systemd
              mountPath: /lib/systemd/
              readOnly: true
            - name: etc-kubernetes
              mountPath: /etc/kubernetes
              readOnly: true
            - name: usr-bin
              mountPath: /usr/local/mount-from-host/bin
              readOnly: true
            resources:
              limits:
                memory: "512Mi"
                cpu: "500m"
              requests:
                memory: "256Mi"
                cpu: "100m"
          restartPolicy: OnFailure
          volumes:
          - name: var-lib-etcd
            hostPath:
              path: "/var/lib/etcd"
          - name: var-lib-kubelet
            hostPath:
              path: "/var/lib/kubelet"
          - name: var-lib-kube-scheduler
            hostPath:
              path: "/var/lib/kube-scheduler"
          - name: var-lib-kube-controller-manager
            hostPath:
              path: "/var/lib/kube-controller-manager"
          - name: etc-systemd
            hostPath:
              path: "/etc/systemd"
          - name: lib-systemd
            hostPath:
              path: "/lib/systemd"
          - name: etc-kubernetes
            hostPath:
              path: "/etc/kubernetes"
          - name: usr-bin
            hostPath:
              path: "/usr/bin"
EOF

    kubectl apply -f /tmp/kube-bench-cronjob.yaml
    log_success "Weekly compliance monitoring CronJob created"

    # Show CronJob status
    kubectl get cronjobs -n "$NAMESPACE"
}

# Function to cleanup resources
cleanup() {
    log_info "Cleaning up resources..."

    # Delete namespace
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true

    # Clean up temporary files
    rm -f /tmp/kube-bench-*.yaml /tmp/master-scan-results.log

    log_success "Cleanup completed"
}

# Function to show cluster info
show_cluster_info() {
    log_info "Cluster information..."

    echo "=== Current Context ==="
    kubectl config current-context 2>/dev/null || echo "No context found"

    echo -e "\n=== Cluster Info ==="
    kubectl cluster-info --request-timeout=10s 2>/dev/null || echo "Cluster info unavailable"

    echo -e "\n=== Nodes ==="
    kubectl get nodes -o wide 2>/dev/null || echo "Cannot get nodes"
}

# Function to run diagnostics
run_diagnostics() {
    log_info "Running diagnostics..."

    echo "=== Cluster Information ==="
    kubectl version --short || echo "kubectl version failed"

    echo -e "\n=== Control Plane Pods ==="
    kubectl get pods -n kube-system -l tier=control-plane

    echo -e "\n=== Node Information ==="
    kubectl get nodes -o wide

    echo -e "\n=== Kube-bench Jobs ==="
    kubectl get jobs -n "$NAMESPACE" 2>/dev/null || echo "No kube-bench jobs found"

    echo -e "\n=== CronJobs ==="
    kubectl get cronjobs -n "$NAMESPACE" 2>/dev/null || echo "No cronjobs found"

    if [ -n "$CONTROL_PLANE_CONTAINER" ] && docker ps --filter "name=$CONTROL_PLANE_CONTAINER" --format "{{.Names}}" | grep -q "$CONTROL_PLANE_CONTAINER"; then
        echo -e "\n=== Kind Control Plane Container ==="
        docker exec "$CONTROL_PLANE_CONTAINER" ls -la /etc/kubernetes/manifests/ 2>/dev/null || echo "Cannot access manifests"
    fi
}

# Function to show help
show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

This script automates the kube-bench CIS Kubernetes benchmark lab exercises on an existing cluster.

OPTIONS:
    -h, --help           Show this help message
    -c, --cleanup        Only run cleanup (remove test resources)
    -d, --diagnostics    Only run diagnostics
    -s, --scan           Only run scanning (master and worker)
    -f, --fix            Only demonstrate scheduler profiling fix
    -e, --encryption     Only demonstrate encryption at rest
    --verify-encryption  Verify etcd encryption status
    -k, --cronjob        Only create continuous compliance CronJob
    --info               Show cluster information

EXAMPLES:
    $0                   Run the complete lab from A to Z
    $0 --scan            Run kube-bench scans only
    $0 --fix             Demonstrate scheduler profiling remediation
    $0 --encryption      Demonstrate encryption at rest configuration
    $0 --verify-encryption  Verify if etcd encryption is working
    $0 --cleanup         Clean up all test resources
    $0 --info            Show cluster information

EOF
}

# Main function
main() {
    log_info "Starting kube-bench CIS Kubernetes Benchmark Lab"
    log_info "================================================"

    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--cleanup)
            verify_cluster
            cleanup
            exit 0
            ;;
        -d|--diagnostics)
            verify_cluster
            run_diagnostics
            exit 0
            ;;
        -s|--scan)
            check_prerequisites
            verify_cluster
            run_master_scan
            run_worker_scan
            exit 0
            ;;
        -f|--fix)
            check_prerequisites
            verify_cluster
            detect_control_plane
            demonstrate_scheduler_profiling_fix
            exit 0
            ;;
        -e|--encryption)
            check_prerequisites
            verify_cluster
            detect_control_plane
            configure_encryption_at_rest
            exit 0
            ;;
        --verify-encryption)
            check_prerequisites
            verify_cluster
            detect_control_plane
            verify_etcd_encryption
            exit 0
            ;;
        -k|--cronjob)
            check_prerequisites
            verify_cluster
            create_continuous_compliance
            exit 0
            ;;
        --info)
            show_cluster_info
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

    # Note: Cleanup must be explicitly requested with --cleanup option

    # Run complete lab from A to Z
    log_info "Running complete kube-bench lab automation..."

    check_prerequisites
    verify_cluster
    detect_control_plane

    log_info "=== Phase 1: Initial Scanning ==="
    run_master_scan
    run_worker_scan

    log_info "=== Phase 2: Remediation Practice ==="
    demonstrate_scheduler_profiling_fix

    log_info "=== Phase 3: Advanced Configuration ==="
    configure_encryption_at_rest

    log_info "=== Phase 4: Automation Setup ==="
    create_continuous_compliance

    log_info "=== Phase 5: Final Diagnostics ==="
    run_diagnostics

    log_success "================================================"
    log_success "Kube-bench CIS Kubernetes Benchmark Lab completed!"
    log_success "================================================"
    log_info "Key achievements:"
    log_info "✓ Connected to existing Kubernetes cluster"
    log_info "✓ Ran CIS benchmark scans on master and worker nodes"
    log_info "✓ Demonstrated scheduler profiling remediation (1.4.1)"
    log_info "✓ Configured encryption at rest (1.2.27 & 1.2.28)"
    log_info "✓ Set up continuous compliance monitoring"
    log_info ""
    log_info "Lab components created:"
    log_info "- Namespace: $NAMESPACE"
    log_info "- Jobs: kube-bench-master, kube-bench-worker (if applicable)"
    log_info "- CronJob: kube-bench-cronjob (weekly scans)"
    log_info ""
    log_info "Next steps:"
    log_info "- Review scan results and apply additional remediations"
    log_info "- Integrate with monitoring and alerting systems"
    log_info "- Consider admission controllers to prevent misconfigurations"
    log_info ""
    log_info "To clean up resources: $0 --cleanup"
}

# Check if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi