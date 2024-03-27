#!/bin/sh

set -e
set -x

NS="compute"

# GCP specific:
# NODE="clus0-1"

NODE="kind-worker"

DIR=$(cd "$(dirname "$0")"; pwd -P)

KIND_CONTEXT="kind-kind"
# Switch back to context kubernetes-admin@kubernetes
kubectl config use-context "$KIND_CONTEXT"

# Run on a Kubernetes cluster with LimitRange admission control plugin enable
# see "kubernetes in action" p405
kubectl delete ns -l "compute=true"
kubectl create namespace "$NS"
kubectl label ns "$NS" "compute=true"

kubectl config set-context $(kubectl config current-context) --namespace=$NS

KUBIA_DIR="/tmp/kubernetes-in-action"
if [ ! -d "$KUBIA_DIR" ]; then
    git clone https://github.com/k8s-school/kubernetes-in-action.git /tmp/kubernetes-in-action

fi

cd "$KUBIA_DIR/Chapter14"
POD="requests-pod"
kubectl apply -f "$KUBIA_DIR"/Chapter14/"$POD".yaml
kubectl  wait --for=condition=Ready pods "$POD"

if timeout --foreground 3 kubectl exec -it "$POD" -- top
then
    ink -y "WARN: 'top' has exited for unknow reason"
else
    ink "Exiting from 'top' command"
fi

# INSPECTING A NODE’S CAPACITY
# Exercice: flood the cluster CPU capacity by creation two pods

for i in 2 3 4
do
POD="requests-pod-$i"
cat <<EOF >/tmp/$POD.yaml
apiVersion: v1
kind: Pod
metadata:
  name: $POD
spec:
  containers:
  - image: busybox
    command: ["dd", "if=/dev/zero", "of=/dev/null"]
    name: main
    resources:
      requests:
        cpu: 1500m
        memory: 20Mi
EOF
  kubectl apply -f "/tmp/requests-pod-$i.yaml"
  if [ $i -neq 4 ]
  then
    kubectl wait --for=condition=Ready pods "$POD"
    kubectl describe pod "$POD"
    kubectl describe node "$NODE"
  fi
done

kubectl describe po requests-pod-4
kubectl describe node "$NODE"
kubectl delete po requests-pod-3
kubectl get po
kubectl delete pods requests-pod-4

POD="limited-pod"
kubectl apply -f "$KUBIA_DIR"/Chapter14/"$POD".yaml
kubectl  wait --for=condition=Ready pods "$POD"
kubectl describe pod "$POD"
if timeout 3 kubectl exec -it "$POD" -- top
then
    ink -y "WARN: 'top' has exited for unknow reason"
else
    ink "Exiting from 'top' command"
fi

# LimitRange
kubectl apply -f $DIR/manifest/local-storage-class.yaml
kubectl apply -f "$KUBIA_DIR"/Chapter14/limits.yaml
kubectl apply -f "$KUBIA_DIR"/Chapter14/limits-pod-too-big.yaml && \
    ink -r "ERROR this command should have failed"
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
