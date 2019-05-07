#!/bin/sh

set -e
set -x

# Run on kubeadm cluster
# see "kubernetes in action" p391

KUBIA_DIR="/tmp/kubernetes-in-action"
if [ ! -d "$KUBIA_DIR" ]; then
    git clone https://github.com/luksa/kubernetes-in-action.git /tmp/kubernetes-in-action

fi

kubectl apply -f network-policy-default-deny.yaml
kubectl apply -f network-policy-postgres.yaml
kubectl apply -f network-policy-cart.yaml
kubectl apply -f network-policy-cidr.yaml
kubectl apply -f network-policy-egress.yaml