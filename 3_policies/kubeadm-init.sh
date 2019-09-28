#!/bin/sh

# Create an up and running k8s cluster

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)

WORKDIR="$DIR/../1_kubeadm"

. "$WORKDIR/env.sh"

"$WORKDIR"/create.sh -p