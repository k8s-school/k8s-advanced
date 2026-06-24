#!/bin/bash

# FinOps Lab - Dedicated installer
# Creates a kind cluster (via ktbx) and installs the components required by the
# Cost Management labs:
#   - metrics-server  (feeds CPU/memory metrics to HPA and VPA)
#   - VPA operator    (recommender + updater + admission-controller), installed
#                     with the OFFICIAL autoscaler hack/vpa-up.sh script:
#                     https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/docs/installation.md

set -euxo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)

CLUSTER_NAME="kind"
METRICS_NS="kube-system"
AUTOSCALER_DIR="/tmp/autoscaler"
# vpa-up.sh runs `git switch --detach vertical-pod-autoscaler-${VPA_TAG}`, so the
# working tree MUST contain that tag. We clone directly at the tag below.
VPA_TAG="1.7.0"

# ---------------------------------------------------------------------------
# 1. Create the Kubernetes cluster (skip if it already exists)
# ---------------------------------------------------------------------------
if ! kubectl config get-contexts "kind-${CLUSTER_NAME}" >/dev/null 2>&1; then
    ktbx create --single
fi
kubectl config use-context "kind-${CLUSTER_NAME}"

# ---------------------------------------------------------------------------
# 2. Install metrics-server (VPA prerequisite)
#    --kubelet-insecure-tls is REQUIRED on kind because kubelet serving
#    certificates are self-signed.
# ---------------------------------------------------------------------------
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

helm upgrade --install metrics-server metrics-server/metrics-server \
    --namespace "$METRICS_NS" \
    --set 'args={--kubelet-insecure-tls}'

kubectl rollout status deployment/metrics-server -n "$METRICS_NS" --timeout=180s

# Wait until metrics are actually served (the API can take a few seconds)
ink -b "Waiting for metrics-server to serve metrics..."
deadline=$((SECONDS + 180))
until kubectl top nodes >/dev/null 2>&1; do
    [ $SECONDS -ge $deadline ] && ink -r "metrics-server did not serve metrics within 180s"
    sleep 5
done
kubectl top nodes

# ---------------------------------------------------------------------------
# 3. Install the Vertical Pod Autoscaler (official method)
#    git clone https://github.com/kubernetes/autoscaler.git
#    cd autoscaler/vertical-pod-autoscaler && ./hack/vpa-up.sh
#    Requires openssl >= 1.1.1 (used to generate the admission webhook certs).
# ---------------------------------------------------------------------------
# Clone shallow but pinned to the VPA release tag so `git switch --detach` works.
if ! git -C "$AUTOSCALER_DIR" rev-parse "vertical-pod-autoscaler-${VPA_TAG}" >/dev/null 2>&1; then
    rm -rf "$AUTOSCALER_DIR"
    git clone --depth 1 --branch "vertical-pod-autoscaler-${VPA_TAG}" \
        https://github.com/kubernetes/autoscaler.git "$AUTOSCALER_DIR"
fi

cd "$AUTOSCALER_DIR/vertical-pod-autoscaler"
# Clean any previous VPA install to keep vpa-up.sh idempotent
./hack/vpa-down.sh || true
./hack/vpa-up.sh

kubectl wait --for=condition=Available -n kube-system --timeout=180s \
    deployment/vpa-recommender deployment/vpa-updater deployment/vpa-admission-controller
kubectl get pods -n kube-system | grep -E "vpa|metrics-server"

ink "FinOps lab environment is ready."
ink "  - metrics-server: namespace ${METRICS_NS}"
ink "  - VPA operator:   namespace kube-system (vpa-recommender / vpa-updater / vpa-admission-controller)"
