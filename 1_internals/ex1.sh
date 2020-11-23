#!/bin/sh

set -e
set -x

# RBAC sa
# see "kubernetes in action" p346

DIR=$(cd "$(dirname "$0")"; pwd -P)

kubectl get pods -n kube-system
kubectl  wait --timeout=120s --for=condition=Ready -n kube-system pods -l component=etcd,tier=control-plane
kubectl get pods -n kube-system
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd,tier=control-plane -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it -n kube-system "$ETCD_POD" --  \
    sh -c "ETCDCTL_API=3 etcdctl --cert /etc/kubernetes/pki/etcd/peer.crt \
    --key /etc/kubernetes/pki/etcd/peer.key --cacert /etc/kubernetes/pki/etcd/ca.crt \
    get /registry --keys-only --prefix"
