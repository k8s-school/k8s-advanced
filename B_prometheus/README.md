# Pre-requisite 

An up and running k8s cluster

WARN: tested on dind-cluster+kubeadm, do not work well on GKE.

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

NODE=clus0-0
# Open ssh tunnel on desktop to grafana
gcloud compute ssh  --ssh-flag="-L 3000:localhost:3000" "$NODE"
```

# Ex2: Install metric-server

Enable 'kubectl top' command and hpa.

```shell
# Hint: https://medium.com/@waleedkhan91/how-to-configure-metrics-server-on-kubeadm-provisioned-kubernetes-cluster-f755a2ac43a2
cd $HOME
git clone https://github.com/kubernetes-incubator/metrics-server
kubectl apply -f metrics-server/deploy/1.8+

# Allow insecure tls, because of self-signed certificate
fjammes15_gmail_com@clus0-0:~/metrics-server$ git diff
diff --git a/deploy/1.8+/metrics-server-deployment.yaml b/deploy/1.8+/metrics-server-deployment.yaml
index 2a8c5fe..2a16d21 100644
--- a/deploy/1.8+/metrics-server-deployment.yaml
+++ b/deploy/1.8+/metrics-server-deployment.yaml
@@ -34,4 +34,7 @@ spec:
         volumeMounts:
         - name: tmp-dir
           mountPath: /tmp
+        command:
+        - /metrics-server
+        - --kubelet-insecure-tls
```

