#!/bin/sh

set -e
set -x

# RBAC clusterrole
# see "kubernetes in action" p362

DIR=$(cd "$(dirname "$0")"; pwd -P)

NS="baz"

# Delete all namespaces, clusterrole, clusterrolebinding, pv
# with label 'RBAC=role' to make current script idempotent
kubectl delete pv,ns,clusterrole,clusterrolebinding -l RBAC=clusterrole

# Create namespace '$NS' in yaml, with label "RBAC=clusterrole"
cat <<EOF >/tmp/ns_$NS.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: $NS
  labels:
    RBAC: clusterrole
EOF
kubectl apply -f "/tmp/ns_$NS.yaml"

# Use namespace 'baz' in current context
kubectl config set-context $(kubectl config current-context) --namespace=$NS

# Create local storage class
kubectl apply -f "$DIR/manifest/local-storage.yaml"

# Create a local PersistentVolume on kube-node-1:/data/disk1
# with label "RBAC=clusterrole"
# see https://kubernetes.io/docs/concepts/storage/volumes/#local
# WARN: Directory kube-node-1:/data/disk1, must exist, 
# for next exercice, create also kube-node-1:/data/disk2
NODE="kube-node-1"
cat <<EOF >/tmp/pv-1.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-1
  labels:
    RBAC: clusterrole
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /data/disk1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $NODE
EOF
kubectl apply -f "/tmp/pv-1.yaml"

# Create clusterrole 'pv-reader' which can get and list resource 'persistentvolumes'
kubectl create clusterrole pv-reader --verb=get,list --resource=persistentvolumes

# Add label "RBAC=clusterrole"
kubectl label clusterrole pv-reader "RBAC=clusterrole"

# Create pod using image 'luksa/kubectl-proxy', and named 'shell' in ns '$NS'
kubectl run --generator=run-pod/v1 shell --image=luksa/kubectl-proxy -n $NS

# Wait for $NS:shell to be in running state
while true
do
    sleep 2
    STATUS=$(kubectl get pods -n $NS shell -o jsonpath="{.status.phase}")
    if [ "$STATUS" = "Running" ]; then
        break
    fi
done

# List persistentvolumes at the cluster scope, with user "system:serviceaccount:$NS:default"
kubectl exec -it -n $NS shell curl localhost:8001/api/v1/persistentvolumes

# Create rolebinding 'pv-reader' which can get and list resource 'persistentvolumes'
kubectl create rolebinding pv-reader --clusterrole=pv-reader --serviceaccount=$NS:default -n $NS

# List again persistentvolumes at the cluster scope, with user "system:serviceaccount:$NS:default"
kubectl exec -it -n $NS shell curl localhost:8001/api/v1/persistentvolumes

# Why does it not work? Find the solution.
kubectl delete rolebinding pv-reader -n $NS
kubectl create clusterrolebinding pv-reader --clusterrole=pv-reader --serviceaccount=$NS:default -n $NS
kubectl label clusterrolebinding pv-reader "RBAC=clusterrole"

# List again persistentvolumes at the cluster scope, with user "system:serviceaccount:$NS:default"
kubectl exec -it -n $NS shell curl localhost:8001/api/v1/persistentvolumes
