#!/bin/sh

# See https://itnext.io/benchmark-results-of-kubernetes-network-plugins-cni-over-10gbit-s-network-36475925a560

set -e
set -x

DIR=$(cd "$(dirname "$0")"; pwd -P)

ID=0
NS="network-$ID"

NODE1_IP=$(kubectl get nodes --selector="! node-role.kubernetes.io/master" \
    -o=jsonpath='{.items[0].status.addresses[0].address}')

# Run on kubeadm cluster
# see "kubernetes in action" p391
kubectl delete ns -l "policies=$NS"
kubectl create namespace "$NS"
kubectl label ns network "policies=$NS"


# Exercice: Install one postgresql pod with helm and add label "tier:database" to master pod
# Disable data persistence
helm delete pgsql --namespace "$NS" || echo "WARN pgsql release not found"

helm repo add bitnami https://charts.bitnami.com/bitnami || echo "Failed to add bitnami repo"
helm repo update

sleep 5
helm install --version 10.4.0 --namespace "$NS" pgsql bitnami/postgresql --set primary.podLabels.tier="database",persistence.enabled="false"

# Install nginx pods
kubectl run -n "$NS" external --image=nginx -l "app=external"
kubectl run -n "$NS" nginx --image=nginx -l "tier=webserver"

kubectl wait --timeout=60s -n "$NS" --for=condition=Ready pods external

kubectl expose -n "$NS" pod external --type=NodePort --port 80 --name=external
# Install netcat, ping, netstat and ps in these pods
kubectl exec -n "$NS" -it external -- \
    sh -c "apt-get update && apt-get install -y dnsutils inetutils-ping netcat net-tools procps tcpdump"

kubectl wait --timeout=60s -n "$NS" --for=condition=Ready pods nginx
kubectl exec -n "$NS" -it nginx -- \
    sh -c "apt-get update && apt-get install -y dnsutils inetutils-ping netcat net-tools procps tcpdump"
sleep 10

# then check what happen with no network policies defined
echo "-------------------"
echo "NO NETWORK POLICIES"
echo "-------------------"
EXTERNAL_IP=$(kubectl get pods -n network external -o jsonpath='{.status.podIP}')
PGSQL_IP=$(kubectl get pods -n network pgsql-postgresql-0 -o jsonpath='{.status.podIP}')
kubectl exec -n "$NS" -it nginx -- netcat -q 2 -nzv ${PGSQL_IP} 5432
kubectl exec -n "$NS" -it nginx -- netcat -q 2 -zv pgsql-postgresql 5432
kubectl exec -n "$NS" -it nginx -- netcat -q 2 -nzv $EXTERNAL_IP 80
kubectl exec -n "$NS" -it external -- netcat -w 2 -zv www.k8s-school.fr 443

# Exercice: Secure communication between webserver and database, and test (webserver, database, external, outside)
