#!/bin/bash

set -euxo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. "$DIR"/../conf.version.sh

# if ink is not defined, define it
if [ -z "$(command -v ink)" ]; then
    ink() {
        echo -e "$@"
    }
fi

ID=$(whoami)

FOO_NAMESPACE="foo-${ID}"
BAR_NAMESPACE="bar-${ID}"

PROXY_POD="curl-custom-sa"

ink "Cleanup"
kubectl delete namespace -l lab=rbac

ink "Creating namespaces..."
kubectl create namespace "$FOO_NAMESPACE"
kubectl create namespace "$BAR_NAMESPACE"
kubectl label namespace "$FOO_NAMESPACE" lab=rbac
kubectl label namespace "$BAR_NAMESPACE" lab=rbac

ink "Deploying kubectl-proxy pod in $FOO_NAMESPACE..."

# Download the kubectl-proxy pod definition
curl -s -o kubectl-proxy.yaml https://raw.githubusercontent.com/k8s-school/k8s-advanced/master/labs/2_authorization/kubectl-proxy.yaml

# Replace the service account name in the pod definition
sed -i "s/serviceAccountName: foo/serviceAccountName: default/" kubectl-proxy.yaml

kubectl apply -f kubectl-proxy.yaml -n "$FOO_NAMESPACE"

ink "Creating services in $FOO_NAMESPACE and $BAR_NAMESPACE..."
kubectl create service clusterip foo-service --tcp=80:80 -n "$FOO_NAMESPACE" || true
kubectl create service clusterip bar-service --tcp=80:80 -n "$BAR_NAMESPACE" || true

ink "Waiting for kubectl-proxy pod to be ready..."
kubectl wait --for=condition=ready pod -n "$FOO_NAMESPACE" --timeout=60s $PROXY_POD

ink "Creating RBAC (Role and RoleBinding) in $FOO_NAMESPACE..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: service-reader
  namespace: $FOO_NAMESPACE
rules:
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list"]
EOF

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: service-reader-binding
  namespace: $FOO_NAMESPACE
subjects:
- kind: ServiceAccount
  name: default
  namespace: $FOO_NAMESPACE
roleRef:
  kind: Role
  name: service-reader
  apiGroup: rbac.authorization.k8s.io
EOF

ink "Running tests inside kubectl-proxy pod..."

ink "Testing access to services in $FOO_NAMESPACE (should succeed)..."
kubectl exec -n "$FOO_NAMESPACE" "$PROXY_POD" -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8001/api/v1/namespaces/"$FOO_NAMESPACE"/services
echo
ink "Testing access to services in $BAR_NAMESPACE (should be forbidden)..."
kubectl exec -n "$FOO_NAMESPACE" "$PROXY_POD" -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8001/api/v1/namespaces/"$BAR_NAMESPACE"/services
echo
ink "Test completed!"

ink "Additional tests:"
ink "Use the patch command, and jsonpatch syntax to add bind foo:service-reader to service account bar:default"
# See http://jsonpatch.com for examples
kubectl patch rolebindings.rbac.authorization.k8s.io -n $FOO_NAMESPACE service-reader-binding --type='json' \
    -p='[{"op": "add", "path": "/subjects/-", "value": {"kind": "ServiceAccount","name": "default","namespace": "'$BAR_NAMESPACE'"} }]'

ink "List service in ns 'foo' with service account bar:default"
kubectl run -n $BAR_NAMESPACE $PROXY_POD --image=k8sschool/kubectl-proxy:$KUBECTL_PROXY_VERSION
kubectl wait -n "$BAR_NAMESPACE" --for=condition=ready pod --timeout=60s $PROXY_POD
kubectl exec -it -n $BAR_NAMESPACE $PROXY_POD -- curl localhost:8001/api/v1/namespaces/$FOO_NAMESPACE/services
