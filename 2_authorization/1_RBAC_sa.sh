#!/bin/sh

set -ex

# RBAC sa
# see "kubernetes in action" p346

DIR=$(cd "$(dirname "$0")"; pwd -P)

kubectl delete sa,pod -l "RBAC=sa"

# Create a service account 'foo'
kubectl create serviceaccount foo
kubectl label sa foo "RBAC=sa"

# Describe secret of this sa, and compare it with default sa
FOO_TOKEN=$(kubectl get sa foo -o jsonpath="{.secrets[0].name}")
kubectl describe secrets "$FOO_TOKEN"

# Create a pod using this service account
# use manifest/pod.yaml, and patch it
kubectl patch -f "$DIR/manifest/pod.yaml" \
    -p '{"spec":{"serviceAccountName":"foo"}}' --local  -o yaml > /tmp/pod.yaml
kubectl apply -f "/tmp/pod.yaml"
kubectl label pod curl-custom-sa "RBAC=sa"

# Wait for pod to be in running state
kubectl wait --for=condition=Ready pods --timeout=180s curl-custom-sa

# Inspect the token mounted into the pod’s container(s)
kubectl exec -it curl-custom-sa -c main \
    cat /var/run/secrets/kubernetes.io/serviceaccount/token
echo

# Talk to the API server with custom ServiceAccount 'foo'
# (tip: use 'main' container inside 'curl-custom-sa' pod)
# If RBAC is enabled, it should not be able to list anything
kubectl exec -it curl-custom-sa -c main -- curl localhost:8001/api/v1/pods
