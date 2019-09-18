#!/bin/sh

set -e
set -x

NS="compute"

DIR=$(cd "$(dirname "$0")"; pwd -P)

# Run on 3_kubeadm to get LimitRange
# see "kubernetes in action" p405
kubectl delete ns -l "compute=true"
kubectl create namespace "$NS"
kubectl label ns "$NS" "compute=true"

kubectl config set-context $(kubectl config current-context) --namespace=$NS

# Test network policies below
    KUBIA_DIR="/tmp/kubernetes-in-action"
if [ ! -d "$KUBIA_DIR" ]; then
    git clone https://github.com/luksa/kubernetes-in-action.git /tmp/kubernetes-in-action

fi

cd "$KUBIA_DIR/Chapter14"

kubectl apply -f "$KUBIA_DIR"/Chapter14/requests-pod.yaml
sleep 5
kubectl exec -it requests-pod top

# INSPECTING A NODE’S CAPACITY
kubectl run requests-pod-2 --image=busybox --restart Never --requests='cpu=800m,memory=20Mi' -- dd if=/dev/zero of=/dev/null
sleep 5
kubectl get po requests-pod-2
# Exercice: flood the cluster CPU capacity by creation two pods
kubectl run requests-pod-3 --image=busybox --restart Never --requests='cpu=1.5,memory=20Mi' -- dd if=/dev/zero of=/dev/null
kubectl run requests-pod-4 --image=busybox --restart Never --requests='cpu=1.5,memory=20Mi' -- dd if=/dev/zero of=/dev/null
kubectl describe po requests-pod-4
kubectl describe node clus0-1
kubectl delete po requests-pod-3
kubectl get po
kubectl delete pods requests-pod-4

kubectl apply -f "$KUBIA_DIR"/Chapter14/limited-pod.yaml
sleep 5
kubectl describe pod limited-pod
kubectl exec -it limited-pod top

# LimitRange
kubectl apply -f $DIR/../3_authorization/manifest/local-storage.yaml
kubectl apply -f "$KUBIA_DIR"/Chapter14/limits.yaml
kubectl apply -f "$KUBIA_DIR"/Chapter14/limits-pod-too-big.yaml && \
    >&2 echo "ERROR this command should have failed"
kubectl apply -f "$KUBIA_DIR"/Chapter03/kubia-manual.yaml

# ResourceQuota
kubectl apply -f "$KUBIA_DIR"/Chapter14/quota-cpu-memory.yaml
kubectl describe quota
# requests.storage is the overall max limit
# https://kubernetes.io/docs/concepts/policy/resource-quotas/#storage-resource-quota
# so there is an inconsistency in example
kubectl apply -f "$KUBIA_DIR"/Chapter14/quota-storage.yaml
kubectl apply -f "$KUBIA_DIR"/Chapter14/quota-object-count.yaml
kubectl apply -f "$KUBIA_DIR"/Chapter14/quota-scoped.yaml


kubectl config set-context $(kubectl config current-context) --namespace=default
