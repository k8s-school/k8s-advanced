#!/bin/sh

# See https://itnext.io/benchmark-results-of-kubernetes-network-plugins-cni-over-10gbit-s-network-36475925a560

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
kubectl apply -f $DIR/../1_kubeadm/resource/psp/default-psp-with-rbac.yaml
helm install --namespace network --name pgsql stable/postgresql --set master.podLabels.tier="database",persistence.enabled="false" --version 3.18.4

# Install nginx pods
kubectl run -n network --generator=run-pod/v1 external --image=nginx
kubectl run -n network --generator=run-pod/v1 nginx --image=nginx -l "tier=webserver"

sleep 5

# Install netcat, ping, netstat and ps in these pods
kubectl exec -n network -it external -- \
    sh -c "apt-get update && apt-get install -y inetutils-ping netcat net-tools procps"
kubectl exec -n network -it nginx -- \
    sh -c "apt-get update && apt-get install -y inetutils-ping netcat net-tools procps"

# Wait for network:external to be in running state
while true
do
    sleep 2
    STATUS=$(kubectl get pods -n network external -o jsonpath="{.status.phase}")
    if [ "$STATUS" = "Running" ]; then
        break
    fi
done

# then
EXTERNAL_IP=$(kubectl get pods -n network external -o jsonpath='{.status.podIP}')
PGSQL_IP=$(kubectl get pods -n network pgsql-postgresql-0 -o jsonpath='{.status.podIP}')
kubectl exec -n network -it nginx -- netcat -q 2 -zv ${PGSQL_IP} 5432
kubectl exec -n network -it nginx -- netcat -q 2 -zv pgsql-postgresql 5432
kubectl exec -n network -it nginx -- netcat -q 2 -nzv $EXTERNAL_IP 80

# Test network policies below
KUBIA_DIR="/tmp/kubernetes-in-action"
if [ ! -d "$KUBIA_DIR" ]; then
    git clone https://github.com/luksa/kubernetes-in-action.git /tmp/kubernetes-in-action

fi

cd "$KUBIA_DIR/Chapter13"
# Edit original file, replace app with tier
kubectl apply -n network -f $DIR/resource/network-policy-postgres.yaml
# Edit original file, replace app with tier
kubectl apply -n network -f $DIR/resource/network-policy-egress.yaml
# Set default deny network policies
# See https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-policies
kubectl apply -n network -f $DIR/resource/network-policy-default-deny.yaml

# Play and test network connections after each step
kubectl exec -n network -it nginx -- netcat -zv pgsql-postgresql 5432
kubectl exec -n network -it nginx -- netcat -nzv $EXTERNAL_IP 80
kubectl exec -n network -it external -- netcat -nzv pgsql-postgresql 5432
kubectl exec -n network -it external -- netcat -zv www.w3.org 80


kubectl apply -n network -f $KUBIA_DIR/Chapter13/network-policy-cart.yaml
kubectl apply -n network -f $KUBIA_DIR/Chapter13/network-policy-cidr.yaml
