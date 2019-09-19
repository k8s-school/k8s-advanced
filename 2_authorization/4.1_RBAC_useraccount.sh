#!/bin/sh

set -e
set -x

# RBAC user
# see Use case 1 in
# https://docs.bitnami.com/kubernetes/how-to/configure-rbac-in-your-kubernetes-cluster/#use-case-1-create-user-with-limited-namespace-access 

DIR=$(cd "$(dirname "$0")"; pwd -P)

KIND_CLUSTER_NAME="kind"
KIND_CONTEXT="kubernetes-admin@kubernetes"
# WARN: Directory kind-worker:/data/disk2, must exist
# on kind run:
# docker exec -it -- kind-worker mkdir -p /data/disk2
# on gcerun:
# ssh clus0-1 -- sudo mkdir -p /data/disk2
PV_NODE="kind-worker"

ORG="hpe"

# Use context 'kubernetes-admin@kind' and delete ns,pv with label "RBAC=user"
kubectl config use-context kubernetes-admin@kind
kubectl delete pv,clusterrolebinding,ns -l "RBAC=user"

# Create namespace 'foo' in yaml, with label "RBAC=clusterrole"
kubectl create ns office
kubectl label ns office "RBAC=user"

CERT_DIR="$HOME/.certs"

kubectl config set-credentials employee --client-certificate="$CERT_DIR/employee.crt" \
    --client-key="$CERT_DIR/employee.key"
kubectl config set-context employee-context --cluster="$KIND_CLUSTER_NAME" --namespace=office \
    --user=employee

kubectl --context=employee-context get pods || \
    >&2 echo "ERROR to get pods"

# Use 'apply' instead of 'create' to create 
# 'role-deployment-manager' and 'rolebinding-deployment-manager'
kubectl apply -f "$DIR/manifest/role-deployment-manager.yaml"

kubectl apply -f "$DIR/manifest/rolebinding-deployment-manager.yaml"

kubectl --context=employee-context run --generator=run-pod/v1 --image bitnami/dokuwiki mydokuwiki
kubectl --context=employee-context get pods

kubectl --context=employee-context get pods --namespace=default || \
    >&2 echo "ERROR to get pods"

# With employee user, try to run a shell in a pod in ns 'office'
kubectl --context=employee-context run --generator=run-pod/v1 -it --image=busybox shell sh || \
    >&2 echo "ERROR to start shell"

# Create a local PersistentVolume on kube-node-1:/data/disk2
# with label "RBAC=user"
# see https://kubernetes.io/docs/concepts/storage/volumes/#local
# WARN: Directory kube-node-1:/data/disk2, must exist

cat <<EOF >/tmp/task-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: task-pv
  labels:
    RBAC: user
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /data/disk2
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $PV_NODE
EOF
kubectl apply -f "/tmp/task-pv.yaml"

# With employee user, create a PersistentVolumeClaim which use pv-1 in ns 'foo'
# See https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/#create-a-persistentvolumeclaim
kubectl --context=employee-context apply -f "$DIR/manifest/pvc.yaml" || 
    >&2 echo "ERROR to create pvc"

# Edit role-deployment-manager.yaml to enable pvc management
kubectl apply -f "$DIR/manifest/role-deployment-manager-pvc.yaml"

# Use context employee-context
kubectl config use-context employee-context

# Try again to create a PersistentVolumeClaim which use pv-1 in ns 'foo'
kubectl --context=employee-context apply -f "$DIR/manifest/pvc.yaml"

# Launch the nginx pod which attach the pvc
kubectl apply -f https://k8s.io/examples/pods/storage/pv-pod.yaml

# Wait for office:task-pv-pod to be in running state
kubectl  wait --for=condition=Ready -n office pods task-pv-pod

# Launch a command in task-pv-pod
kubectl exec -it task-pv-pod echo "SUCCESS in lauching command in task-pv-pod"

# Switch back to context kubernetes-admin@kubernetes
kubectl config use-context "$KIND_CONTEXT"

# Try to get pv using 'employee-context'
kubectl --context=employee-context get pv || 
    >&2 echo "ERROR to get pv"

# Create a 'clusterrolebinding' between clusterrole=pv-reader and group=$ORG
kubectl create clusterrolebinding "pv-reader-$ORG" --clusterrole=pv-reader --group="$ORG"
kubectl label clusterrolebinding "pv-reader-$ORG" "RBAC=user"

# Try to get pv using 'employee-context'
kubectl --context=employee-context get pv

# Exercice: remove pod resource for deployment-manager role and check what happen when creatin a deployment, then a pod?
# Answer: deployment runs ok, but it is not possible to create a pod (think of controllers role)
