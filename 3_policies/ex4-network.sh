#!/bin/sh

# See https://itnext.io/benchmark-results-of-kubernetes-network-plugins-cni-over-10gbit-s-network-36475925a560

set -e
set -x

DIR=$(cd "$(dirname "$0")"; pwd -P)

# Run on kubeadm cluster
# see "kubernetes in action" p391
kubectl delete ns -l "policies=network"
kubectl create namespace network
kubectl label ns network "policies=network"

# Exercice: Install one postgresql pod with helm and add label "tier:database" to master pod
# Disable data persistence

if ! kubectl get deployments -n kube-system tiller-deploy;
then
    helm init
    kubectl create serviceaccount --namespace kube-system tiller
    kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
    kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'
    helm init --service-account tiller --upgrade
else
    helm delete --purge pgsql || echo "WARN pgsql release not found"
fi

helm repo update
helm search postgresql
kubectl apply -f $DIR/../1_kubeadm/resource/psp/default-psp-with-rbac.yaml
sleep 10
helm install --namespace network --name pgsql stable/postgresql --set master.podLabels.tier="database",persistence.enabled="false"

# Install nginx pods
kubectl run -n network --generator=run-pod/v1 external --image=nginx -l "app=external"
kubectl run -n network --generator=run-pod/v1 nginx --image=nginx -l "tier=webserver"

# Wait for network:external to be in running state
while true
do
    sleep 2
    STATUS=$(kubectl get pods -n network external -o jsonpath="{.status.phase}")
    if [ "$STATUS" = "Running" ]; then
        break
    fi
done

kubectl expose -n network pod external --type=NodePort --port 80 --name=external
# Install netcat, ping, netstat and ps in these pods
kubectl exec -n network -it external -- \
    sh -c "apt-get update && apt-get install -y dnsutils inetutils-ping netcat net-tools procps tcpdump"
kubectl exec -n network -it nginx -- \
    sh -c "apt-get update && apt-get install -y dnsutils inetutils-ping netcat net-tools procps tcpdump"
sleep 10


# then
EXTERNAL_IP=$(kubectl get pods -n network external -o jsonpath='{.status.podIP}')
PGSQL_IP=$(kubectl get pods -n network pgsql-postgresql-0 -o jsonpath='{.status.podIP}')
kubectl exec -n network -it nginx -- netcat -q 2 -nzv ${PGSQL_IP} 5432
kubectl exec -n network -it nginx -- netcat -q 2 -zv pgsql-postgresql 5432
kubectl exec -n network -it nginx -- netcat -q 2 -nzv $EXTERNAL_IP 80

# Test network policies below
KUBIA_DIR="/tmp/kubernetes-in-action"
if [ ! -d "$KUBIA_DIR" ]; then
    git clone https://github.com/k8s-school/kubernetes-in-action.git /tmp/kubernetes-in-action

fi

cd "$KUBIA_DIR/Chapter13"

# Exercice: Secure communication between webserver and database, and test (webserver, database, external, outside)
# Enable DNS access, see https://docs.projectcalico.org/v3.7/security/advanced-policy#5-allow-dns-egress-traffic
kubectl label namespace kube-system name=kube-system
kubectl apply -n network -f $DIR/resource/allow-dns-access.yaml

# Edit original file, replace app with tier
kubectl apply -n network -f $DIR/resource/ingress-www-db.yaml
# Edit original file, replace app with tier
kubectl apply -n network -f $DIR/resource/egress-www-db.yaml
# Set default deny network policies
# See https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-policies
kubectl apply -n network -f $DIR/resource/default-deny.yaml

# Play and test network connections after each step
kubectl exec -n network -it nginx -- netcat -q 2 -nzv ${PGSQL_IP} 5432
kubectl exec -n network -it nginx -- netcat -q 2 -zv pgsql-postgresql 5432
kubectl exec -n network -it nginx -- netcat -w 2 -nzv $EXTERNAL_IP 80
kubectl exec -n network -it external -- netcat -w 2 -zv pgsql-postgresql 5432
kubectl exec -n network -it external -- netcat -w 2 -zv www.w3.org 80
# Ip for www.w3.org
kubectl exec -n network -it external -- netcat -w 2 -nzv 128.30.52.100 80

# Exercice: open NodePort
# - use tcpdump inside host/pod to get source IP address
# 'tcpdump port 30657 -i any'
NODE_PORT=$(kubectl get svc external -n network  -o jsonpath="{.spec.ports[0].nodePort}")
curl --connect-timeout 2 http://clus0-1:${NODE_PORT}
kubectl apply -n network -f $DIR/resource/ingress-external.yaml
curl http://clus0-1:${NODE_PORT}

# TODO: try to open NodePort with CIDR
# May not be possible,
# see https://github.com/projectcalico/canal/issues/87,
# and https://docs.projectcalico.org/v3.7/security/host-endpoints/tutorial#content-main
kubectl apply -n network -f $DIR/resource/ingress-external-ipblock.yaml
kubectl apply -n network -f $KUBIA_DIR/Chapter13/network-policy-cart.yaml

