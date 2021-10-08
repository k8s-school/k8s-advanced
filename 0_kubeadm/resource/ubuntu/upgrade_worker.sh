#!/bin/sh

# Upgrade a worker node

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)
. "$DIR/../env.sh"

sudo apt-get update -q

sudo kubeadm upgrade node

sudo apt-get update -q
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get install -y kubectl="$LATEST_KUBEADM" kubelet="$LATEST_KUBEADM" \
    kubeadm="$LATEST_KUBEADM" --allow-downgrades
sudo apt-mark hold kubeadm kubelet kubectl

sudo systemctl restart kubelet
sudo systemctl status kubelet
