#!/bin/bash

set -e

# Maximum wait time in seconds (default: 600 seconds = 10 minutes)
TIMEOUT="${1:-600}"
SLEEP_INTERVAL=5
START_TIME=$(date +%s)

echo "⏳ Waiting for the Kubernetes API server to become reachable..."

# Wait for the Kubernetes API server (port 6443) to respond
until curl -k --silent https://localhost:6443/version > /dev/null 2>&1; do
  if (( $(date +%s) - START_TIME > TIMEOUT )); then
    echo "❌ Timeout: API server is still unreachable after $TIMEOUT seconds."
    exit 1
  fi
  sleep $SLEEP_INTERVAL
done

echo "✅ API server is reachable."

echo "⏳ Waiting for all kube-system pods to be ready..."

# Wait until all kube-system pods are in Running or Completed state
while true; do
  if (( $(date +%s) - START_TIME > TIMEOUT )); then
    echo "❌ Timeout: kube-system pods are not ready after $TIMEOUT seconds."
    kubectl get pods -n kube-system
    exit 1
  fi

  NOT_READY=$(kubectl get pods -n kube-system -l tier=control-plane --no-headers 2>/dev/null | grep -vE 'Running|Completed|STATUS' | wc -l)

  if [ "$NOT_READY" -eq 0 ]; then
    echo "✅ All kube-system pods are ready."
    break
  fi

  sleep $SLEEP_INTERVAL
done

echo "⏳ Verifying that CRDs can be applied (OpenAPI schema is ready)..."

DUMMY_CRD=$(mktemp)
cat <<EOF > "$DUMMY_CRD"
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: dummytests.example.com
spec:
  group: example.com
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
  scope: Namespaced
  names:
    plural: dummytests
    singular: dummytest
    kind: DummyTest
EOF

while true; do
  if (( $(date +%s) - START_TIME > TIMEOUT )); then
    echo "❌ Timeout: API server not ready for CRDs (OpenAPI schema issue)."
    exit 1
  fi

  if kubectl apply --dry-run=server -f "$DUMMY_CRD" &>/dev/null; then
    break
  fi

  sleep $SLEEP_INTERVAL
done

echo "✅ API server is fully ready to accept CRDs."
rm -f "$DUMMY_CRD"

echo "🎉 Kubernetes master is ready!"
