# Pre-requisite 

An up and running k8s cluster

NOTE: Successfully tested on kind-v0.5.1 (2019-09-28)

# Pre-requisite: Initialize helm

See [script](../A_elasticsearch/helm_init.sh)

# Ex1: Install prometheus-operator

Detailed documentation is available here:
https://itnext.io/kubernetes-monitoring-with-prometheus-in-15-minutes-8e54d1de2e13

```shell
# on dind run: helm init
# on kubeadm/gke see in A_elasticsearch
helm install stable/prometheus-operator --name prometheus-operator --namespace monitoring

# Prometheus access:
kubectl port-forward -n monitoring prometheus-prometheus-operator-prometheus-0 9090 &

# Grafana access:
# login as admin with password prom-operator
kubectl port-forward $(kubectl get  pods --selector=app=grafana -n  monitoring --output=jsonpath="{.items..metadata.name}") -n monitoring  3000 &

# GCE specific
NODE=clus0-0
# Open ssh tunnel on desktop to grafana
gcloud compute ssh  --ssh-flag="-nNT -L 3000:localhost:3000" "$NODE"
```

# Ex2: Install metric-server

NOTE: Successfully tested on kind-v0.5.1 (2019-09-28)

Enable 'kubectl top' command and hpa.

```shell
# Hint: https://medium.com/@waleedkhan91/how-to-configure-metrics-server-on-kubeadm-provisioned-kubernetes-cluster-f755a2ac43a2
cd $HOME
git clone https://github.com/kubernetes-incubator/metrics-server

# Allow insecure tls, because of self-signed certificate
fjammes@[kubectl]:~/metrics-server $ git diff
diff --git a/deploy/1.8+/metrics-server-deployment.yaml b/deploy/1.8+/metrics-server-deployment.yaml
index 07cb865..e2912e4 100644
--- a/deploy/1.8+/metrics-server-deployment.yaml
+++ b/deploy/1.8+/metrics-server-deployment.yaml
@@ -34,4 +34,6 @@ spec:
         volumeMounts:
         - name: tmp-dir
           mountPath: /tmp
-
+        args:
+        - --kubelet-insecure-tls
+        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname

# Create metrics-server and wait for it to work
kubectl apply -f metrics-server/deploy/1.8+
```

