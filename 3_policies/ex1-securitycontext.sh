#!/bin/sh

set -e
set -x

# Run on 1_kubeadm
# see "kubernetes in action" p375

KIA_DIR="/tmp/kubernetes-in-action"

if [ ! -d "$KIA_DIR" ]
then
    git clone https://github.com/k8s-school/kubernetes-in-action.git "$KIA_DIR"
else
    cd "$KIA_DIR"
    git pull
fi

cd "$KIA_DIR/Chapter13"

NS="security-context"
kubectl delete ns -l "$NS=true"
kubectl create ns "$NS"
kubectl label ns "$NS" "$NS=true"

kubectl config set-context $(kubectl config current-context) --namespace="$NS"

POD="pod-with-host-network"
kubectl apply -f "$POD.yaml"
kubectl wait --timeout=60s --for=condition=Ready pods "$POD"
kubectl exec "$POD" -- ifconfig

kubectl apply -f kubia-hostport.yaml
# Run 'curl http://localhost:9000' on host

POD="pod-with-host-pid-and-ipc"
kubectl apply -f "$POD.yaml"
kubectl wait --timeout=60s --for=condition=Ready pods "$POD"
kubectl exec "$POD" -- ps aux

# RUNNING A POD WITHOUT SPECIFYING A SECURITY CONTEXT
POD="pod-with-defaults"
kubectl run "$POD" --restart=Never --image alpine --restart Never -- /bin/sleep 999999
kubectl wait --timeout=60s --for=condition=Ready pods "$POD"
kubectl exec "$POD" -- id

POD="pod-as-user-guest"
kubectl apply -f "$POD.yaml"
kubectl wait --timeout=60s --timeout=30s --for=condition=Ready pods "$POD"
kubectl exec "$POD" -- id
kubectl exec "$POD" -- cat /etc/passwd

kubectl apply -f pod-run-as-non-root.yaml
kubectl get po pod-run-as-non-root

POD="pod-privileged"
kubectl apply -f "$POD.yaml"
kubectl wait --timeout=60s --for=condition=Ready pods "$POD"
kubectl exec "$POD" -- ls /dev
kubectl exec -it pod-with-defaults -- ls /dev
kubectl exec -it pod-with-defaults -- date +%T -s "12:00:00"

POD="pod-add-settime-capability"
kubectl apply -f "$POD.yaml"
kubectl wait --timeout=60s --for=condition=Ready pods "$POD"
# WARN: might break the cluster
# kubectl exec "$POD"  -- date +%T -s "12:00:00"

# Dropping capabilities from a container
kubectl exec pod-with-defaults -- chown guest /tmp
kubectl exec pod-with-defaults -- ls -la / | grep tmp

POD="pod-drop-chown-capability"
kubectl apply -f "$POD.yaml"
kubectl wait --timeout=60s --for=condition=Ready pods "$POD"
kubectl exec "$POD" -- chown guest /tmp && >&2 echo "ERROR this command should have failed"

# 13.2.6 Preventing processes from writing to the container’s filesystem
POD="pod-with-readonly-filesystem"
kubectl apply -f "$POD.yaml"
kubectl wait --timeout=60s --for=condition=Ready pods "$POD"
kubectl exec "$POD" -- touch /new-file && >&2 echo "ERROR this command should have failed"
kubectl exec -it "$POD" -- touch /volume/newfile
kubectl exec -it "$POD" -- ls -la /volume/newfile

# 13.2.7 Sharing volumes when containers run as different users
POD="pod-with-shared-volume-fsgroup"
kubectl apply -f "$POD.yaml"
kubectl wait --timeout=60s --for=condition=Ready pods "$POD"
kubectl exec -it "$POD"  -c first -- sh -c "id && \
    ls -l / | grep volume && \
    echo foo > /volume/foo && \
    ls -l /volume && \
    echo foo > /tmp/foo && \
    ls -l /tmp"
