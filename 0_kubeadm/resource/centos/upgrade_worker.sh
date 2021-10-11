#!/bin/sh

# Upgrade a worker node

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)
. "$DIR/../env.sh"

sudo kubeadm upgrade node config --kubelet-version "$BUMP_K8S"

sudo apt-get update -q
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get install -y kubectl="$BUMP_KUBEADM" kubelet="$BUMP_KUBEADM" \
    kubeadm="$BUMP_KUBEADM"
sudo apt-mark hold kubeadm kubelet kubectl

sudo systemctl restart kubelet
sudo systemctl status kubelet
