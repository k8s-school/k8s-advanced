#!/bin/bash

# Install Istio
# Check https://istio.io/docs/setup/getting-started/

set -euxo pipefail

NS="istio-system"

DIR=$(cd "$(dirname "$0")"; pwd -P)

. "$DIR"/env.sh


echo "Download istio (version $ISTIO_VERSION)"
if [ ! -d "$ISTIO_DIR" ]; then
    curl -L https://git.io/getLatestIstio | ISTIO_VERSION="$ISTIO_VERSION" sh -
fi
cd "$ISTIO_DIR"
istioctl manifest apply --set profile=demo

kubectl get svc -n "$NS"

