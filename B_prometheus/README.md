# Pre-requisite 

An up and running k8s cluster

NOTE: Successfully tested on kind-v0.6.1 (2020-01-10) and helm-v3.0.1

# Ex1: Install prometheus-operator

```shell
./install.sh

# Prometheus access:
kubectl port-forward -n monitoring prometheus-prometheus-stack-kube-prom-prometheus-0 9090

# Grafana access:
# login as admin with password prom-operator
kubectl port-forward $(kubectl get  pods --selector=app.kubernetes.io/name=grafana -n  monitoring --output=jsonpath="{.items..metadata.name}") -n monitoring  3000 &

# Alertmanager UI access
kubectl port-forward -n monitoring svc/alertmanager-operated 9093:9093 

```



# Ex2: Install metric-server

NOTE: Successfully tested on kind-v0.6.1 (2020-01-10)

Enable 'kubectl top' command and hpa.

```shell

# See https://github.com/kubernetes-incubator/metrics-server
wget https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.3.7/components.yaml

# Allow insecure tls, because of self-signed certificate
diff -u2 components.yaml.1 components.yaml 
--- components.yaml.1	2020-08-25 09:20:38.000000000 +0200
+++ components.yaml	2020-09-22 23:46:05.873971737 +0200
@@ -89,4 +89,5 @@
           - --cert-dir=/tmp
           - --secure-port=4443
+          - --kubelet-insecure-tls
         ports:
         - name: main-port

# Create metrics-server and wait for it to work
kubectl apply -f components.yaml
```

