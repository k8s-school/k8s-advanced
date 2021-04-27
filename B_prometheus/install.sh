#!/bin/bash

## Install prometheus stack

set -euxo pipefail

NS="monitoring"

# TODO hack, implement nicely helm delete
helm delete prometheus-stack -n monitoring || echo "Unable to delete prometheus stack"

kubectl delete ns -l name="$NS"
kubectl create namespace "$NS"
kubectl label ns "$NS" "name=$NS"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || echo "Unable to add repo prometheus-community"
helm repo add stable https://charts.helm.sh/stable --force-update
helm repo update
helm install --version 12.2.2 prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring

