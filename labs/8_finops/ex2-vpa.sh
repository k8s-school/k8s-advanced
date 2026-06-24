#!/bin/bash

# FinOps Lab 2 - Vertical Pod Autoscaling (VPA)
# Deploy a workload with deliberately low CPU/memory requests, then let the VPA
# recommender compute right-sized requests. First in "Off" (recommendation
# only) mode, then in "Recreate" mode where the VPA evicts & recreates pods with
# the recommended values.

set -euxo pipefail

# Per-user namespace so several students can share the same cluster.
NS="vpa-demo-${USER:-$(id -un)}"

kubectl delete ns "$NS" --ignore-not-found
kubectl create namespace "$NS"
kubectl config set-context "$(kubectl config current-context)" --namespace="$NS"

# ---------------------------------------------------------------------------
# 1. Deploy a CPU-burning workload with under-sized requests
# ---------------------------------------------------------------------------
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hamster
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hamster
  template:
    metadata:
      labels:
        app: hamster
    spec:
      containers:
      - name: hamster
        image: registry.k8s.io/ubuntu-slim:0.14
        resources:
          requests:
            cpu: 50m
            memory: 50Mi
        command: ["/bin/sh"]
        args:
        - "-c"
        - "while true; do timeout 0.5s yes >/dev/null; sleep 0.5s; done"
EOF
kubectl rollout status deployment/hamster --timeout=120s

# ---------------------------------------------------------------------------
# 2. Create a VPA in "Off" mode: recommendations only, no pod disruption
# ---------------------------------------------------------------------------
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: hamster-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: hamster
  updatePolicy:
    updateMode: "Off"
EOF

# The recommender needs a few minutes of metrics history before emitting advice
ink -b "Waiting for the VPA recommender to produce recommendations..."
deadline=$((SECONDS + 300))
until kubectl get vpa hamster-vpa -o jsonpath='{.status.recommendation.containerRecommendations}' 2>/dev/null | grep -q "target"; do
    [ $SECONDS -ge $deadline ] && ink -r "VPA recommender produced no recommendation within 300s"
    sleep 15
    kubectl get vpa hamster-vpa || true
done

ink "===== VPA recommendation (target = suggested requests) ====="
kubectl describe vpa hamster-vpa | sed -n '/Recommendation/,/Events/p'

# ---------------------------------------------------------------------------
# 3. Switch to "Recreate" mode: the VPA will evict pods and recreate them with
#    the recommended requests.
#    NB: the old "Auto" mode is deprecated since VPA 1.7.0 in favour of the
#    explicit modes "Recreate", "Initial" and "InPlaceOrRecreate".
# ---------------------------------------------------------------------------
kubectl patch vpa hamster-vpa --type merge -p '{"spec":{"updatePolicy":{"updateMode":"Recreate"}}}'

ink -b "VPA in Recreate mode. Watching pods get recreated with right-sized requests (~3 min)..."
end=$((SECONDS + 180))
while [ $SECONDS -lt $end ]; do
    kubectl get pods -o custom-columns=\
'NAME:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory'
    sleep 30
done

# ---------------------------------------------------------------------------
# 4. (Bonus) "InPlaceOrRecreate": resize the running pods WITHOUT recreating
#    them. Requires the In-Place Pod Resize feature, stable on Kubernetes 1.33+.
#    Skipped automatically on older clusters (it would silently fall back to
#    Recreate).
# ---------------------------------------------------------------------------
# Read the SERVER minor version. `kubectl get --raw /version` returns only the
# server version (no client/server skew confusion).
SERVER_MINOR=$(kubectl get --raw /version | grep -oE '"minor": *"[0-9]+' | grep -oE '[0-9]+$')
if [ "${SERVER_MINOR:-0}" -ge 33 ]; then
    ink -b "Cluster >= 1.33: demonstrating in-place resize (no pod recreation)."

    # Record current pod names + start times to prove they are NOT recreated
    BEFORE=$(kubectl get pods -l app=hamster \
        -o jsonpath='{range .items[*]}{.metadata.name}{" started="}{.status.startTime}{"\n"}{end}')
    echo "BEFORE:"; printf '%s\n' "$BEFORE"

    kubectl patch vpa hamster-vpa --type merge \
        -p '{"spec":{"updatePolicy":{"updateMode":"InPlaceOrRecreate"}}}'

    ink -b "Watching requests change in place (~3 min). Same pod NAME + startTime = resized live."
    end=$((SECONDS + 180))
    while [ $SECONDS -lt $end ]; do
        kubectl get pods -l app=hamster -o custom-columns=\
'NAME:.metadata.name,START:.status.startTime,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory'
        sleep 30
    done
else
    ink -y "Cluster < 1.33: skipping the InPlaceOrRecreate bonus (in-place resize not available)."
fi

kubectl config set-context "$(kubectl config current-context)" --namespace=default
