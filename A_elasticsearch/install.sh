#!/bin/bash

set -euxo pipefail

# WARN does not work in dind
# see https://platform9.com/blog/kubernetes-logging-and-monitoring-the-elasticsearch-fluentd-and-kibana-efk-stack-part-2-elasticsearch-configuration/

NS="logging"

helm delete elasticsearch || echo "elasticsearch not found"
helm delete fluentd || echo "fluentd not found"
helm delete kibana || echo "kibana not found"

kubectl delete ns -l name="logging"
kubectl create namespace "$NS"
kubectl label ns "$NS" name="logging"

helm repo add elastic https://helm.elastic.co
helm repo update

# Install elasticsearch
helm install elasticsearch elastic/elasticsearch --namespace "$NS" --set data.terminationGracePeriodSeconds=0
# \
#    --set master.persistence.enabled=false --set data.persistence.enabled=false

# Install fluentd
helm install fluentd --namespace "$NS" elastic/filebeat

# Install Kibana
helm install kibana --namespace "$NS" elastic/kibana

# Generate logs
./generate-log.sh > /dev/null &

POD_NAME=$(kubectl get pods --namespace "$NS" -l "app=kibana,release=kibana" -o jsonpath="{.items[0].metadata.name}")

# Wait for kibana to be in running state
kubectl wait -n "$NS" --for=condition=Ready pods "$POD_NAME"

kubectl port-forward -n "$NS" "$POD_NAME" 5601 &
# In Kibana, go to "Discover", add "logstash*" index and "@timestamp" filter, then go to "Discover"
