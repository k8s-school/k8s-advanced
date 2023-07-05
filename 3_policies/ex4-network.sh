#!/bin/bash

# See https://itnext.io/benchmark-results-of-kubernetes-network-plugins-cni-over-10gbit-s-network-36475925a560

set -euxo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)
EX4_NETWORK_FULL="${EX4_NETWORK_FULL:-false}"


ID=0
NS="network-$ID"

NODE1_IP=$(kubectl get nodes --selector="! node-role.kubernetes.io/master" \
    -o=jsonpath='{.items[0].status.addresses[0].address}')

# Run on kubeadm cluster
# see "kubernetes in action" p391
kubectl delete ns -l "policies=$NS"
kubectl create namespace "$NS"
kubectl label ns "$NS" "policies=$NS"

# Exercice: Install one postgresql pod with helm and add label "tier:database" to master pod
# Disable data persistence
helm delete pgsql --namespace "$NS" || echo "WARN pgsql release not found"

helm repo add bitnami https://charts.bitnami.com/bitnami || echo "Failed to add bitnami repo"
helm repo update

helm install --version 11.9.1 --namespace "$NS" pgsql bitnami/postgresql --set primary.podLabels.tier="database",persistence.enabled="false"

# Install nginx pods
kubectl run -n "$NS" external --image=nginx -l "app=external"
kubectl run -n "$NS" nginx --image=nginx -l "tier=webserver"

kubectl wait --timeout=60s -n "$NS" --for=condition=Ready pods external

kubectl expose -n "$NS" pod external --type=NodePort --port 80 --name=external
# Install netcat, ping, netstat and ps in these pods
kubectl exec -n "$NS" -it external -- \
    sh -c "apt-get update && apt-get install -y dnsutils inetutils-ping netcat-traditional net-tools procps tcpdump"

kubectl wait --timeout=60s -n "$NS" --for=condition=Ready pods nginx
kubectl exec -n "$NS" -it nginx -- \
    sh -c "apt-get update && apt-get install -y dnsutils inetutils-ping netcat-traditional net-tools procps tcpdump"

# Wait for pgsql pods to be ready
kubectl wait --for=condition=Ready -n "$NS" pods -l app.kubernetes.io/instance=pgsql

# then check what happen with no network policies defined
echo "-------------------"
echo "NO NETWORK POLICIES"
echo "-------------------"
EXTERNAL_IP=$(kubectl get pods -n "$NS" external -o jsonpath='{.status.podIP}')
PGSQL_IP=$(kubectl get pods -n "$NS" pgsql-postgresql-0 -o jsonpath='{.status.podIP}')
echo "XXXXXXXXXXXXXXXXXXXXXXXxx DEBUG"
kubectl get svc -n "$NS"
kubectl get endpoints -n "$NS"
echo "XXXXXXXXXXXXXXXXXXXXXXXxx DEBUG"
kubectl exec -n "$NS" nginx -- netcat -q 2 -nzv ${PGSQL_IP} 5432
kubectl exec -n "$NS" nginx -- netcat -q 2 -zv pgsql-postgresql 5432
kubectl exec -n "$NS" nginx -- netcat -q 2 -nzv $EXTERNAL_IP 80
kubectl exec -n "$NS" external -- netcat -w 2 -zv www.k8s-school.fr 443

echo "EXERCICE: Secure communication between webserver and database, and test (webserver, database, external, outside)"

if [ "$EX4_NETWORK_FULL" = false ]
then
    exit 0
fi

# Enable DNS access, see https://docs.projectcalico.org/v3.7/security/advanced-policy#5-allow-dns-egress-traffic
kubectl apply -n "$NS" -f $DIR/resource/allow-dns-access.yaml

# Edit original file, replace app with tier
kubectl apply -n "$NS" -f $DIR/resource/ingress-www-db.yaml
# Edit original file, replace app with tier
kubectl apply -n "$NS" -f $DIR/resource/egress-www-db.yaml
# Set default deny network policies
# See https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-policies
kubectl apply -n "$NS" -f $DIR/resource/default-deny.yaml

# Play and test network connections after each step
echo "---------------------"
echo "WITH NETWORK POLICIES"
echo "---------------------"
kubectl exec -n "$NS" nginx -- netcat -q 2 -nzv ${PGSQL_IP} 5432
kubectl exec -n "$NS" nginx -- netcat -w 2 -nzv $EXTERNAL_IP 80 && >&2 echo "ERROR this command should have failed"
kubectl exec -n "$NS" external -- netcat -w 2 -zv pgsql-postgresql 5432 && >&2 echo "ERROR this command should have failed"
kubectl exec -n "$NS" external -- netcat -w 2 -zv www.k8s-school.fr 80 && >&2 echo "ERROR this command should have failed"
# Ip for www.w3.org
kubectl exec -n "$NS" external -- netcat -w 2 -nzv 128.30.52.100 80 && >&2 echo "ERROR this command should have failed"

# Exercice: open NodePort
# - use tcpdump inside host/pod to get source IP address
# 'tcpdump port 30657 -i any'
NODE_PORT=$(kubectl get svc external -n "$NS"  -o jsonpath="{.spec.ports[0].nodePort}")
curl --connect-timeout=2 "http://${NODE1_IP}:${NODE_PORT}" && >&2 echo "ERROR this command should have failed"
kubectl apply -n "$NS" -f $DIR/resource/ingress-external.yaml
while ! curl -connect-timeout=2 "http://${NODE1_IP}:${NODE_PORT}"
do
  # cilium require some time to enable this networkpolicy
  echo "waiting for networkpolicy: ingress to external pod"
  sleep 2
done

# TODO: try to open NodePort with CIDR
# May not be possible,
# see https://github.com/projectcalico/canal/issues/87,
# and https://docs.projectcalico.org/v3.7/security/host-endpoints/tutorial#content-main
kubectl apply -n "$NS" -f $DIR/resource/ingress-external-ipblock.yaml

# Test network policies below
KUBIA_DIR="/tmp/kubernetes-in-action"
if [ ! -d "$KUBIA_DIR" ]; then
    git clone https://github.com/k8s-school/kubernetes-in-action.git /tmp/kubernetes-in-action

fi

kubectl apply -n "$NS" -f $KUBIA_DIR/Chapter13/network-policy-cart.yaml

