#!/bin/bash

# Install Istio
# Check https://istio.io/docs/setup/getting-started/

set -euxo pipefail

NS="istio-system"

kubectl -n "$NS" port-forward $(kubectl -n "$NS" get pod -l app=kiali -o jsonpath='{.items[0].metadata.name}') 20001:20001 &
echo "Kiali access: http://localhost:20001"

kubectl -n "$NS" port-forward $(kubectl -n "$NS" get pod -l app=jaeger -o jsonpath='{.items[0].metadata.name}') 15032:16686 &
echo "Jaeger access: http://localhost:15032"

kubectl -n "$NS" port-forward $(kubectl -n "$NS" get pod -l app=grafana -o jsonpath='{.items[0].metadata.name}') 3000:3000 &
echo "Grafana access: http://localhost:3000"