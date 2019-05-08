#!/bin/sh

set -e
set -x

DIR=$(cd "$(dirname "$0")"; pwd -P)

# Run on kubeadm cluster
# see "kubernetes in action" p391
kubectl create namespace network
kubectl label ns network "policies=network"

# Exercice: Install one postgresql pod with helm and add label "tier:database" to master pod
# Disable data persistence
helm init
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'   
helm init --service-account tiller --upgrade
sleep 5
helm repo update
helm search postgresql
helm install -n network --name pgsql stable/postgresql --set master.podLabels.tier="database",persistence.enabled="false" --version 3.18.4

# Install nginx pod with netcat
kubectl run -n network --generator=run-pod/v1 nginx --image=nginx -l "tier=webserver" -- sh -c "apt-get update && apt-get install -y netcat && sleep 3600"
sleep 10
PGSQL_IP=$(kubectl get pods pgsql-postgresql-0 -o jsonpath='{.status.podIP}')
kubectl exec -n network -it nginx -- netcat -zv ${PGSQL_IP} 5432 

# Create service from pgsql?

# Check network connection from webserver to pgsql using netcat

# Test network policies below


KUBIA_DIR="/tmp/kubernetes-in-action"
if [ ! -d "$KUBIA_DIR" ]; then
    git clone https://github.com/luksa/kubernetes-in-action.git /tmp/kubernetes-in-action

fi

cd "$KUBIA_DIR/Chapter13"
kubectl apply -n network -f $DIR/resource/network-policy-default-deny.yaml
# Edit this file, replace app with tier
kubectl apply -n network -f $DIR/resource/network-policy-postgres.yaml
kubectl apply -n network -f network-policy-cart.yaml
kubectl apply -n network -f network-policy-cidr.yaml
kubectl apply -n network -f network-policy-egress.yaml
