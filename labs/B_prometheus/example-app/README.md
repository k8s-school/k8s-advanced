**Work in progress, do not work yet**

# Ex1: Install prometheus-operator

Detailed documentation is available here:
https://itnext.io/kubernetes-monitoring-with-prometheus-in-15-minutes-8e54d1de2e13

```shell
# See https://sysdig.com/blog/kubernetes-monitoring-prometheus/#howtomonitorakubernetesservicewithprometheus
kubectl create -f https://raw.githubusercontent.com/mateobur/prometheus-monitoring-guide/master/traefik-prom.yaml
# See https://stackoverflow.com/questions/52991038/how-to-create-a-servicemonitor-for-prometheus-operator
kubectl apply -f servicemonitor.yaml
```
