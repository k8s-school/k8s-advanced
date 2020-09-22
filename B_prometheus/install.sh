#!/bin/bash

## Install prometheus stack

set -euxo pipefail

NS="monitoring"

# TODO hack, implement nicely helm delete
helm delete prometheus-stack -n monitoring || echo "Unable to delete prometheus stack"

kubectl delete ns -l name="$NS"
kubectl create namespace "$NS"
kubectl label ns "$NS" "name=$NS"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add stable https://kubernetes-charts.storage.googleapis.com/
helm repo update
helm install prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring

