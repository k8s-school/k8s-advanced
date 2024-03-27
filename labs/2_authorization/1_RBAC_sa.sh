#!/bin/bash

set -euxo pipefail

# RBAC sa
# see "kubernetes in action" p346

DIR=$(cd "$(dirname "$0")"; pwd -P)

kubectl delete sa,pod -l "RBAC=sa"

# Create a service account 'foo'
kubectl create serviceaccount foo
kubectl label sa foo "RBAC=sa"

# Create a pod using this service account
# use manifest/pod.yaml, and patch it
kubectl patch -f "$DIR/manifest/pod.yaml" \
    -p '{"spec":{"serviceAccountName":"foo"}}' --local  -o yaml > /tmp/pod.yaml
kubectl apply -f "/tmp/pod.yaml"
kubectl label pod curl-custom-sa "RBAC=sa"

# Wait for pod to be in running state
kubectl wait --for=condition=Ready pods --timeout=180s curl-custom-sa

# Inspect the token mounted into the pod’s container(s)
kubectl exec -it curl-custom-sa -c main -- \
    cat /var/run/secrets/kubernetes.io/serviceaccount/token
echo

kubectl delete pod curl-custom-sa

# Create secret for this SA (no longer needed since k8S 1.24)
ink -y "WARNING: security exposure of persisting a non-expiring token credential in a readable API object"
FOO_TOKEN="foo-token"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
 name: $FOO_TOKEN
 annotations:
   kubernetes.io/service-account.name: foo
type: kubernetes.io/service-account-token
EOF

kubectl describe secret "$FOO_TOKEN"

# Recreate pod
kubectl patch -f "$DIR/manifest/pod.yaml" \
    -p '{"spec":{"serviceAccountName":"foo"}}' --local  -o yaml > /tmp/pod.yaml
kubectl apply -f "/tmp/pod.yaml"
kubectl label pod curl-custom-sa "RBAC=sa"

# Wait for pod to be in running state
kubectl wait --for=condition=Ready pods --timeout=180s curl-custom-sa

# Inspect the token mounted into the pod’s container(s)
kubectl exec -it curl-custom-sa -c main -- \
    cat /var/run/secrets/kubernetes.io/serviceaccount/token
echo

# Talk to the API server with custom ServiceAccount 'foo'
# (tip: use 'main' container inside 'curl-custom-sa' pod)
# If RBAC is enabled, it should not be able to list anything
kubectl exec -it curl-custom-sa -c main -- curl localhost:8001/api/v1/pods

ink "Non mandatory, check expiry date on https://jwt.io/"
kubectl create token foo
