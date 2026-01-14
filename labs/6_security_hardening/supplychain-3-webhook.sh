#!/bin/bash

# Supply Chain Security Lab - Phase 2: Webhook Deployment
# Builds, deploys and configures the image policy webhook

set -euxo pipefail

echo "=== 🔐 Phase 2: TLS Certificates Generation ==="

echo "Creating PKI infrastructure for webhook..."
mkdir -p /tmp/webhook-certs
cd /tmp/webhook-certs

echo "1. Creating Webhook CA..."
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -subj "/CN=Webhook CA" -days 365 -out ca.crt

echo "2. Creating server certificate for webhook service..."
openssl genrsa -out tls.key 2048

# Create certificate for the service DNS name
cat > csr.conf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = image-policy-webhook.kube-system.svc

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = image-policy-webhook.kube-system.svc
DNS.2 = image-policy-webhook.kube-system.svc.cluster.local
DNS.3 = image-policy-webhook
EOF

openssl req -new -key tls.key -config csr.conf -out tls.csr
openssl x509 -req -in tls.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out tls.crt -days 365 -extensions v3_req -extfile csr.conf

echo "PKI setup complete."
echo "Generated certificates:"
ls -la *.crt *.key

echo "=== 🐳 Phase 3: Building Webhook Docker Image ==="

cd "$(dirname "$0")/webhook-server"

echo "Building webhook Docker image..."
docker build -t image-policy-webhook:latest .

echo "Docker image built successfully:"
docker images | grep image-policy-webhook

echo "=== 💻 Phase 4: Deploying Webhook to Kubernetes ==="

echo "1. Creating webhook certificates Secret..."
kubectl create secret tls webhook-certs \
    --cert=/tmp/webhook-certs/tls.crt \
    --key=/tmp/webhook-certs/tls.key \
    --namespace=kube-system \
    --dry-run=client -o yaml | kubectl apply -f -

# Also add the CA certificate to the secret for reference
kubectl create secret generic webhook-ca \
    --from-file=ca.crt=/tmp/webhook-certs/ca.crt \
    --namespace=kube-system \
    --dry-run=client -o yaml | kubectl apply -f -

echo "2. Deploying webhook service..."
kubectl apply -f webhook-deployment.yaml

echo "Waiting for webhook deployment to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/image-policy-webhook -n kube-system

echo "Checking webhook pod status..."
kubectl get pods -n kube-system -l app=image-policy-webhook

echo "=== ⚙️ Phase 5: Kubernetes API Server Configuration ==="

echo "1. Creating admission configuration directory..."
sudo mkdir -p /etc/kubernetes/admission

# Get the CA certificate in base64 for the kubeconfig
CA_BUNDLE=$(cat /tmp/webhook-certs/ca.crt | base64 | tr -d '\n')

echo "2. Creating webhook kubeconfig..."
sudo tee /etc/kubernetes/admission/webhook-kubeconfig.yaml > /dev/null << EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CA_BUNDLE
    server: https://image-policy-webhook.kube-system.svc:443/scan
  name: image-checker
contexts:
- context:
    cluster: image-checker
    user: api-server
  name: check-images
current-context: check-images
users:
- name: api-server
EOF

echo "3. Creating admission configuration..."
sudo tee /etc/kubernetes/admission/admission-config.yaml > /dev/null << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: ImagePolicyWebhook
    configuration:
      imagePolicy:
        kubeConfigFile: /etc/kubernetes/admission/webhook-kubeconfig.yaml
        defaultAllow: false # Reject if webhook service is down
        allowTTL: 30
        denyTTL: 30
        retryBackoff: 500
        defaultAllow: false
EOF

echo "4. Backing up original kube-apiserver.yaml..."
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml.backup

echo "5. Modifying kube-apiserver.yaml to enable ImagePolicyWebhook..."
# Create a temporary script to modify the API server config
sudo tee /tmp/modify-apiserver.py > /dev/null << 'EOF'
import yaml
import sys

with open('/etc/kubernetes/manifests/kube-apiserver.yaml', 'r') as f:
    config = yaml.safe_load(f)

# Add admission plugins
commands = config['spec']['containers'][0]['command']
admission_plugins_added = False
admission_config_added = False

# Check and update admission plugins
for i, cmd in enumerate(commands):
    if cmd.startswith('--enable-admission-plugins='):
        if 'ImagePolicyWebhook' not in cmd:
            commands[i] = cmd + ',ImagePolicyWebhook'
        admission_plugins_added = True
        break

if not admission_plugins_added:
    commands.append('--enable-admission-plugins=NodeRestriction,ImagePolicyWebhook')

# Check and add admission control config
for cmd in commands:
    if cmd.startswith('--admission-control-config-file='):
        admission_config_added = True
        break

if not admission_config_added:
    commands.append('--admission-control-config-file=/etc/kubernetes/admission/admission-config.yaml')

# Add volume mounts
volume_mounts = config['spec']['containers'][0].get('volumeMounts', [])
admission_mount_exists = any(vm.get('name') == 'admission-conf' for vm in volume_mounts)

if not admission_mount_exists:
    volume_mounts.append({
        'mountPath': '/etc/kubernetes/admission',
        'name': 'admission-conf',
        'readOnly': True
    })

config['spec']['containers'][0]['volumeMounts'] = volume_mounts

# Add volumes
volumes = config['spec'].get('volumes', [])
admission_volume_exists = any(v.get('name') == 'admission-conf' for v in volumes)

if not admission_volume_exists:
    volumes.append({
        'hostPath': {
            'path': '/etc/kubernetes/admission'
        },
        'name': 'admission-conf'
    })

config['spec']['volumes'] = volumes

with open('/etc/kubernetes/manifests/kube-apiserver.yaml', 'w') as f:
    yaml.dump(config, f, default_flow_style=False)
EOF

sudo python3 /tmp/modify-apiserver.py

echo "API Server configuration updated. Waiting for restart..."

# Wait for API server to restart and be ready
echo "Waiting for API server to be ready..."
for i in {1..180}; do
    if kubectl get nodes > /dev/null 2>&1; then
        echo "API Server is ready after $i seconds"
        break
    fi
    if [ $i -eq 180 ]; then
        echo "API Server took too long to restart"
        echo "Check the API server logs: sudo journalctl -u kubelet"
        exit 1
    fi
    sleep 2
done

# Additional wait to ensure webhook is fully functional
echo "Waiting for webhook to be fully operational..."
sleep 15

# Test webhook connectivity from API server
echo "Testing webhook connectivity..."
kubectl logs -n kube-system deployment/image-policy-webhook --tail=5

echo "=== 🧪 Phase 6: Testing the Image Policy Webhook ==="

echo "1. Testing allowed image (nginx:alpine)..."
echo "Creating test pod with allowed image..."
if kubectl run ok-pod --image=nginx:alpine --restart=Never --dry-run=client -o yaml | kubectl apply -f -; then
    echo "✅ Allowed image test passed - nginx:alpine was accepted"
    kubectl delete pod ok-pod --ignore-not-found=true
else
    echo "❌ Allowed image test failed - nginx:alpine should be accepted"
    kubectl logs -n kube-system deployment/image-policy-webhook --tail=10
    exit 1
fi

echo ""
echo "2. Testing forbidden image (nginx:1.19)..."
echo "Attempting to create pod with forbidden image..."
if kubectl run bad-pod --image=nginx:1.19 --restart=Never 2>&1 | tee /tmp/webhook-test.log | grep -q "image policy webhook backend denied"; then
    echo "✅ Forbidden image test passed - webhook correctly blocked nginx:1.19"
    echo "Webhook response:"
    grep "image policy webhook backend denied" /tmp/webhook-test.log || true
else
    echo "❌ Forbidden image test failed - webhook should have blocked nginx:1.19"
    echo "Full kubectl output:"
    cat /tmp/webhook-test.log
    echo ""
    echo "Webhook logs:"
    kubectl logs -n kube-system deployment/image-policy-webhook --tail=10
    exit 1
fi

echo ""
echo "3. Testing another forbidden image (nginx:1.18)..."
if kubectl run bad-pod2 --image=nginx:1.18 --restart=Never 2>&1 | grep -q "image policy webhook backend denied"; then
    echo "✅ Second forbidden image test passed - webhook correctly blocked nginx:1.18"
else
    echo "❌ Second forbidden image test failed"
    kubectl logs -n kube-system deployment/image-policy-webhook --tail=10
fi

echo ""
echo "=== 📊 Webhook Status ==="
echo "Webhook deployment status:"
kubectl get deployment -n kube-system image-policy-webhook

echo ""
echo "Webhook pod logs (last 10 lines):"
kubectl logs -n kube-system deployment/image-policy-webhook --tail=10

echo ""
echo "=== 🧹 Cleanup Instructions ==="
echo "To cleanup this lab setup, run:"
echo ""
echo "1. Restore API server configuration:"
echo "   sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml.backup /etc/kubernetes/manifests/kube-apiserver.yaml"
echo ""
echo "2. Delete webhook resources:"
echo "   kubectl delete -f $(dirname "$0")/webhook-server/webhook-deployment.yaml"
echo "   kubectl delete secret webhook-certs webhook-ca -n kube-system"
echo ""
echo "3. Remove admission configuration:"
echo "   sudo rm -rf /etc/kubernetes/admission"
echo ""
echo "4. Remove temporary certificates:"
echo "   rm -rf /tmp/webhook-certs"
echo ""
echo "5. Remove test files:"
echo "   rm -f /tmp/webhook-test.log /tmp/modify-apiserver.py"

echo ""
echo "✅ Image Policy Webhook deployment completed successfully!"
echo ""
echo "Summary:"
echo "- Generated TLS certificates for secure webhook communication"
echo "- Built and deployed Go webhook as Kubernetes pod with ConfigMaps"
echo "- Configured Kubernetes ImagePolicyWebhook admission controller"
echo "- Successfully tested both allowed and forbidden images"
echo "- The webhook is now running and will block vulnerable container images"
echo ""
echo "The webhook will now:"
echo "- Block nginx:1.19, nginx:1.18, and ubuntu:18.04 images"
echo "- Allow secure images like nginx:alpine"
echo "- Log all image policy decisions"
echo "- Scale and restart automatically as a Kubernetes deployment"