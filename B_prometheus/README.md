# Pre-requisite 

An up and running k8s cluster

NOTE: Successfully tested on kind-v0.6.1 (2020-01-10) and helm-v3.0.1

# Ex1: Install prometheus-operator

```shell
kubectl create namespace monitoring
helm repo add stable https://kubernetes-charts.storage.googleapis.com/
helm install prometheus-operator stable/prometheus-operator --namespace monitoring

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

NOTE: Successfully tested on kind-v0.6.1 (2020-01-10)

Enable 'kubectl top' command and hpa.

```shell
# Hint: https://medium.com/@waleedkhan91/how-to-configure-metrics-server-on-kubeadm-provisioned-kubernetes-cluster-f755a2ac43a2
cd $HOME
git clone https://github.com/kubernetes-incubator/metrics-server

# Allow insecure tls, because of self-signed certificate
fjammes@[k8s-toolbox]:~/k8s-advanced/B_prometheus/metrics-server # git diff
diff --git a/deploy/1.8+/metrics-server-deployment.yaml b/deploy/1.8+/metrics-server-deployment.yaml
index b84d9c3..52a2769 100644
--- a/deploy/1.8+/metrics-server-deployment.yaml
+++ b/deploy/1.8+/metrics-server-deployment.yaml
@@ -33,6 +33,8 @@ spec:
         args:
           - --cert-dir=/tmp
           - --secure-port=4443
+          - --kubelet-insecure-tls
+          - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
         ports:
         - name: main-port
           containerPort: 4443

# Create metrics-server and wait for it to work
kubectl apply -f metrics-server/deploy/1.8+
```

