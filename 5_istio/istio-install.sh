#!/bin/bash

# Install Istio
# Check https://istio.io/docs/setup/getting-started/

set -euxo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)
. "$DIR"/env.sh

NS="istio-system"

echo "Download istio (version $ISTIO_VERSION)"
if [ ! -d "$ISTIO_DIR" ]; then
    cd "$ISTIO_PARENT_DIR"
    curl -L https://git.io/getLatestIstio | ISTIO_VERSION="$ISTIO_VERSION" sh -
fi
cd "$ISTIO_DIR"
istioctl manifest apply --set profile=demo

kubectl get svc -n "$NS"

