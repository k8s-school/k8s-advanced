#!/bin/bash

set -euo pipefail
shopt -s expand_aliases

DIR=$(cd "$(dirname "$0")"; pwd -P)

. $DIR/../conf.version.sh

EX4_NETWORK_FULL="${EX4_NETWORK_FULL:-false}"

usage() {
  cat << EOD

Usage: `basename $0` [options]

  Available options:
    -h         this message
    -s         run exercice and solution

Run network exercice
EOD
}

# get the options
while getopts hs c ; do
    case $c in
	    h) usage ; exit 0 ;;
	    s) EX4_NETWORK_FULL=true ;;
	    \?) usage ; exit 2 ;;
    esac
done
shift `expr $OPTIND - 1`

if [ $# -ne 0 ] ; then
    usage
    exit 2
fi

ID="$(whoami)"
NS="network-$ID"


# Run on kubeadm cluster
# see "kubernetes in action" p391
kubectl delete ns -l "kubernetes.io/metadata.name=$NS"
kubectl create namespace "$NS"

set +x
ink 'Install one postgresql pod with helm and add label "tier:database"'
ink "Disable data persistence"
set -x
if ! helm delete pgsql --namespace "$NS"
then
    set +x
    ink -y "WARN pgsql instance not found"
    set -x
fi

if ! helm repo add bitnami https://charts.bitnami.com/bitnami
then
    set +x
    ink -y "WARN Failed to add bitnami repo"
    set -x
fi
helm repo update

set +x
ink "Install postgresql database with helm"
set -x
helm install --version 11.9.1 --namespace "$NS" pgsql bitnami/postgresql --set primary.podLabels.tier="database",persistence.enabled="false"

set +x
ink "Create external pod"
set -x
kubectl run -n "$NS" external --image=nginx:$NGINX_VERSION -l "app=external"
set +x
ink "Create webserver pod"
set -x
kubectl run -n "$NS" webserver --image=nginx:$NGINX_VERSION -l "tier=webserver"

kubectl wait --timeout=60s -n "$NS" --for=condition=Ready pods external

kubectl expose -n "$NS" pod external --type=NodePort --port 80 --name=external
set +x
ink "Install netcat, ping, netstat and ps in these pods"
set -x
kubectl exec -n "$NS" -it external -- \
    sh -c "apt-get update && apt-get install -y dnsutils inetutils-ping netcat-traditional net-tools"

kubectl wait --timeout=60s -n "$NS" --for=condition=Ready pods webserver
kubectl exec -n "$NS" -it webserver -- \
    sh -c "apt-get update && apt-get install -y dnsutils inetutils-ping netcat-traditional net-tools"

set +x
ink "Wait for pgsql pods to be ready"
set -x
kubectl wait --for=condition=Ready -n "$NS" pods -l app.kubernetes.io/instance=pgsql

set +x
ink "Check what happen with no network policies defined"
ink -b "++++++++++++++++++++"
ink -b "NO NETWORK POLICIES"
ink -b "++++++++++++++++++++"
set -x
EXTERNAL_IP=$(kubectl get pods -n "$NS" external -o jsonpath='{.status.podIP}')
PGSQL_IP=$(kubectl get pods -n "$NS" pgsql-postgresql-0 -o jsonpath='{.status.podIP}')
set +x
ink "webserver to database"
set -x
kubectl exec -n "$NS" webserver -- netcat -q 2 -nzv ${PGSQL_IP} 5432
set +x
ink "webserver to database, using DNS name"
set -x
kubectl exec -n "$NS" webserver -- netcat -q 2 -zv pgsql-postgresql 5432
set +x
ink "webserver to outside external pod"
set -x
kubectl exec -n "$NS" webserver -- netcat -q 2 -nzv $EXTERNAL_IP 80
set +x
ink "external to outside world"
set -x
kubectl exec -n "$NS" external -- netcat -w 2 -zv www.k8s-school.fr 443

set +x
ink -b "EXERCICE: Secure communication between webserver and database, and validate it (webserver, database, external, outside)"
set -x
if [ "$EX4_NETWORK_FULL" = false ]
then
    exit 0
fi

set +x
ink "Enable DNS access, see https://docs.projectcalico.org/v3.7/security/advanced-policy#5-allow-dns-egress-traffic"
set -x
kubectl apply -n "$NS" -f $DIR/resource/allow-dns-access.yaml

# Edit original file, replace app with tier
kubectl apply -n "$NS" -f $DIR/resource/ingress-www-db.yaml
# Edit original file, replace app with tier
kubectl apply -n "$NS" -f $DIR/resource/egress-www-db.yaml
ink "Set default deny network policies"
# See https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-policies
kubectl apply -n "$NS" -f $DIR/resource/default-deny.yaml

set +x
ink "Check what happen with network policies defined"
ink -b "+---------------------+"
ink -b "WITH NETWORK POLICIES"
ink -b "+---------------------+"
set -x
set +x
ink "webserver to database"
set -x
kubectl exec -n "$NS" webserver -- netcat -q 2 -nzv ${PGSQL_IP} 5432
set +x
ink "webserver to database, using DNS name"
set -x
kubectl exec -n "$NS" webserver -- netcat -q 2 -zv pgsql-postgresql 5432
set +x
ink "webserver to external pod"
set -x
if kubectl exec -n "$NS" webserver -- netcat -q 2 -nzv $EXTERNAL_IP 80
then
    set +x
    ink -r "ERROR this connection should have failed"
    exit 1
    set -x
else
    set +x
    ink -y "Connection failed"
    set -x
fi
set +x
ink "external pod to database"
set -x
if kubectl exec -n "$NS" external -- netcat -w 2 -zv pgsql-postgresql 5432
then
    set +x
    ink -r "ERROR this connection should have failed"
    exit 1
    set -x
else
    set +x
    ink -y "Connection failed"
    set -x
fi
set +x
ink "external pod to outside world"
set -x
if kubectl exec -n "$NS" external -- netcat -w 2 -zv www.k8s-school.fr 80
then
    set +x
    ink -r "ERROR this connection should have failed"
    exit 1
    set -x
else
    set +x
    ink -y "Connection failed"
    set -x
fi
