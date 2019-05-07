#!/bin/sh

set -e
set -x

# Run on 1_kubeadm
# see "kubernetes in action" p375

git clone https://github.com/luksa/kubernetes-in-action.git /tmp/kubernetes-in-action
cd /tmp/kubernetes-in-action/Chapter13

kubectl apply -f pod-with-host-network.yaml
kubectl exec pod-with-host-network ifconfig
kubectl apply -f kubia-hostport.yaml
# Run 'curl http://localhost:9000' on host
kubectl apply -f pod-with-host-pid-and-ipc.yaml
kubectl exec pod-with-host-pid-and-ipc ps aux

# RUNNING A POD WITHOUT SPECIFYING A SECURITY CONTEXT
kubectl run pod-with-defaults --image alpine --restart Never -- /bin/sleep 999999
kubectl exec pod-with-defaults id

kubectl apply -f pod-as-user-guest.yaml
kubectl exec pod-as-user-guest id
kubectl exec pod-as-user-guest cat /etc/passwd

kubectl apply -f pod-run-as-non-root.yaml
kubectl get po pod-run-as-non-root

kubectl apply -f pod-privileged.yaml
kubectl exec -it pod-with-defaults ls /dev
kubectl exec -it pod-privileged ls /dev
kubectl exec -it pod-with-defaults -- date +%T -s "12:00:00"

kubectl apply -f pod-add-settime-capability.yaml
kubectl exec -it pod-add-settime-capability -- date +%T -s "12:00:00"

# Dropping capabilities from a container
kubectl exec pod-with-defaults chown guest /tmp
kubectl exec pod-with-defaults -- ls -la / | grep tmp

kubectl apply -f pod-drop-chown-capability.yaml

kubectl exec pod-drop-chown-capability chown guest /tmp && >&2 echo "ERROR this command should have failed"

# 13.2.6 Preventing processes from writing to the container’s filesystem
kubectl apply -f pod-with-readonly-filesystem.yaml
sleep 5
kubectl exec -it pod-with-readonly-filesystem touch /new-file >&2 echo "ERROR this command should have failed"
kubectl exec -it pod-with-readonly-filesystem touch /volume/newfile
kubectl exec -it pod-with-readonly-filesystem -- ls -la /volume/newfile

# 13.2.7 Sharing volumes when containers run as different users
kubectl apply -f pod-with-shared-volume-fsgroup.yaml
kubectl exec -it pod-with-shared-volume-fsgroup -c first -- sh -c "id && \
    ls -l / | grep volume && \
    echo foo > /volume/foo && \
    ls -l /volume && \
    echo foo > /tmp/foo && \
    ls -l /tmp"