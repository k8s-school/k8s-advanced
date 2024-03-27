#!/bin/bash

set -euo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)

. $DIR/../conf.version.sh


readonly DIR=$(cd "$(dirname "$0")"; pwd -P)

NS="demo-pod-security"
kubectl delete namespace -l "kubernetes.io/metadata.name=$NS"

kubectl create namespace "$NS"
kubectl config set-context $(kubectl config current-context) --namespace=$NS
ink -y "Set pod-security to warn=restricted"
ink -y "###################################"
ink -y "label namespace $NS 'pod-security.kubernetes.io/warn=restricted'"
set -x
kubectl label namespace "$NS" "pod-security.kubernetes.io/warn=restricted"
set +x
ink "Create privileged pod 1"
set -x
kubectl run privileged-pod1 --image=busybox:$BUSYBOX_VERSION --privileged
kubectl get pod privileged-pod1
set +x

ink -y "Set pod-security to enforce=restricted"
ink -y "######################################"
set -x
ink -y "label namespace $NS 'pod-security.kubernetes.io/enforce=restricted'"
kubectl label namespace "$NS" "pod-security.kubernetes.io/enforce=restricted"
set +x
ink "Delete privileged pod 1"
set -x
kubectl delete pod privileged-pod1 --now
set +x
ink "Create privileged pod 2"
set -x
if ! kubectl run privileged-pod2 --image=busybox:$BUSYBOX_VERSION --privileged
then
    set +x
    ink -r "EXPECTED ERROR: Privileged pod 2 not allowed"
else
    set +x
    ink -r "ERROR Privileged pod allowed"
    exit 1
fi