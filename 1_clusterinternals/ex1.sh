#!/bin/sh

set -e
set -x

# RBAC sa
# see "kubernetes in action" p346

DIR=$(cd "$(dirname "$0")"; pwd -P)

kubectl exec -it -n kube-system etcd-kind-control-plane --  \
    sh -c "ETCDCTL_API=3 etcdctl --cert /etc/kubernetes/pki/etcd/peer.crt \
    --key /etc/kubernetes/pki/etcd/peer.key --cacert /etc/kubernetes/pki/etcd/ca.crt \
    get /registry --keys-only --prefix"
