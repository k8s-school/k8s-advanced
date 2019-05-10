# Pre-requisite 

An up and running k8s cluster

WARN: tested on dind-cluster.

# Install premetheus-operator

## Use helm

Detailed documentation is available here:
https://itnext.io/kubernetes-monitoring-with-prometheus-in-15-minutes-8e54d1de2e13

```shell
helm init
helm install stable/prometheus-operator --name prometheus-operator --namespace monitoring

# Prometheus access:
kubectl port-forward -n monitoring prometheus-prometheus-operator-prometheus-0 9090 &

# Grafana access:
# login as admin with password prom-operator
kubectl port-forward $(kubectl get  pods --selector=app=grafana -n  monitoring --output=jsonpath="{.items..metadata.name}") -n monitoring  3000 &
```


