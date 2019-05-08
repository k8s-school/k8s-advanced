#!/bin/sh

set -e
set -x

# Run on kubeadm cluster
# see "kubernetes in action" p391

# Exercice: Install one postgresql pod with helm and add label "tier:database" to master pod
# Disable data persistence
helm init
sleep 5
helm repo update
helm search postgresql
helm install --name pgsql stable/postgresql --set master.podLabels.tier="database",persistence.enabled="false" --version 3.18.4

# Install nginx pod with netcat
kubectl run -it --generator=run-pod/v1 nginx --image=nginx -l "tier=webserver" -- sh -c "apt-get update && apt-get install -y netcat && netcat -zv 10.244.3.5 5432 && sleep 3600"

# Create service from pgsql?

# Check network connection from webserver to pgsql using netcat

# Test network policies below


KUBIA_DIR="/tmp/kubernetes-in-action"
if [ ! -d "$KUBIA_DIR" ]; then
    git clone https://github.com/luksa/kubernetes-in-action.git /tmp/kubernetes-in-action

fi

kubectl apply -f network-policy-default-deny.yaml
kubectl apply -f network-policy-postgres.yaml
kubectl apply -f network-policy-cart.yaml
kubectl apply -f network-policy-cidr.yaml
kubectl apply -f network-policy-egress.yaml
