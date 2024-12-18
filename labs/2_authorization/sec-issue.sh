#!/bin/bash

# Inject a security issue inside a k8s cluster

set -euxo pipefail

NS="monitor"

kubectl create namespace "$NS"
kubectl create clusterrolebinding cluster-monitoring --clusterrole=cluster-admin --serviceaccount=monitor:default

# To find it use "rbac-tool analysis", and then
# Same command than "kubens monitoring"
kubectl config set-context $(kubectl config current-context) --namespace="$NS"
SERVICE_ACCOUNT_NAME="default"
kubectl get rolebinding,clusterrolebinding --all-namespaces -o jsonpath="{range .items[?(@.subjects[0].name=='$SERVICE_ACCOUNT_NAME')]}[role: {.roleRef.kind},{.roleRef.name}, binding: {.metadata.name}]{end}"
