#!/bin/bash

set -euxo pipefail

# WARN does not work in dind
# see https://platform9.com/blog/kubernetes-logging-and-monitoring-the-elasticsearch-fluentd-and-kibana-efk-stack-part-2-elasticsearch-configuration/

NS="logging"

helm delete -n $NS elasticsearch || echo "elasticsearch not found"
helm delete -n $NS fluentd || echo "fluentd not found"
helm delete -n $NS kibana || echo "kibana not found"

kubectl delete ns -l name="logging"
kubectl create namespace "$NS"
kubectl label ns "$NS" name="logging"

helm repo add elastic https://helm.elastic.co
helm repo update

# Fail due to security enhancement
VERSION=8.5.1
VERSION=7.17.3

# Install elasticsearch
helm install --version "$VERSION" elasticsearch elastic/elasticsearch --namespace "$NS" --set data.terminationGracePeriodSeconds=0
# \
#    --set master.persistence.enabled=false --set data.persistence.enabled=false

# Install fluentd
helm install fluentd --version "$VERSION" --namespace "$NS" elastic/filebeat

# Install Kibana
helm install kibana --version "$VERSION" --namespace "$NS" elastic/kibana

# Generate logs
./generate-log.sh > /dev/null &

POD_NAME=$(kubectl get pods --namespace "$NS" -l "app=kibana,release=kibana" -o jsonpath="{.items[0].metadata.name}")

# Wait for kibana to be in running state
kubectl wait -n "$NS" --for=condition=Ready pods "$POD_NAME"

kubectl port-forward -n "$NS" "$POD_NAME" 5601 &
echo 'In Kibana, go to "Discover", add "filebeat-7.17.3*" index and "@timestamp" filter'
echo 'then go to "Discover" and search on "Connecting"'
