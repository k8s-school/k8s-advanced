#!/bin/bash

# FinOps Lab 1 - Horizontal Pod Autoscaling (HPA)
# Deploy the classic php-apache CPU-bound workload, attach an HPA, generate
# load and observe Kubernetes scale the number of replicas out and back in.

set -euxo pipefail

# Per-user namespace so several students can share the same cluster.
NS="hpa-demo-${USER:-$(id -un)}"

kubectl delete ns "$NS" --ignore-not-found
kubectl create namespace "$NS"
kubectl config set-context "$(kubectl config current-context)" --namespace="$NS"

# ---------------------------------------------------------------------------
# 1. Deploy the php-apache CPU-intensive workload
# ---------------------------------------------------------------------------
kubectl apply -f https://k8s.io/examples/application/php-apache.yaml
kubectl rollout status deployment/php-apache --timeout=120s

# ---------------------------------------------------------------------------
# 2. Create the HorizontalPodAutoscaler
#    Target: 50% average CPU, between 1 and 10 replicas.
# ---------------------------------------------------------------------------
kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=10

# Wait for the HPA to read the first metrics (TARGETS must leave <unknown>).
# kubectl autoscale creates an autoscaling/v2 HPA, so the utilization lives in
# .status.currentMetrics[].resource.current.averageUtilization (0 is valid).
ink -b "Waiting for HPA to collect metrics..."
deadline=$((SECONDS + 180))
until kubectl get hpa php-apache \
    -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null \
    | grep -qE '^[0-9]+$'; do
    [ $SECONDS -ge $deadline ] && ink -r "HPA did not collect metrics within 180s"
    sleep 10
    kubectl get hpa php-apache || true
done
kubectl get hpa php-apache

# ---------------------------------------------------------------------------
# 3. Generate load with a busybox client hammering the service
# ---------------------------------------------------------------------------
kubectl run load-generator --image=busybox:1.36 --restart=Never -- \
    /bin/sh -c "while true; do wget -q -O- http://php-apache; done"

ink -b "Load generator started. Watching HPA scale OUT for ~3 minutes..."
end=$((SECONDS + 180))
while [ $SECONDS -lt $end ]; do
    kubectl get hpa php-apache
    kubectl get deployment php-apache
    sleep 20
done

# ---------------------------------------------------------------------------
# 4. Stop the load and observe scale IN
# ---------------------------------------------------------------------------
kubectl delete pod load-generator --ignore-not-found
ink -y "Load removed. The HPA will scale back down after its stabilization window (~5 min)."
kubectl get hpa php-apache
kubectl get deployment php-apache

kubectl config set-context "$(kubectl config current-context)" --namespace=default
