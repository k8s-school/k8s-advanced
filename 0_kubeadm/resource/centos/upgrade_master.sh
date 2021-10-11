#!/bin/sh

set -e
set -x

DIR=$(cd "$(dirname "$0")"; pwd -P)
. "$DIR/../env.sh"

sudo cp -f $DIR/kubeadm-config.yaml /etc/kubeadm

# On whole control plane
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm="$BUMP_KUBEADM"
sudo apt-mark hold kubeadm
kubeadm version

# On master node only
kubectl wait --for=condition=ready node clus0-0
sudo kubeadm upgrade plan "$BUMP_K8S"
sudo kubeadm upgrade apply -y "$BUMP_K8S"

# On whole control plane
sudo apt-mark unhold kubelet kubectl
sudo apt-get update -q
sudo apt-get install -y kubelet="$BUMP_KUBEADM" kubectl="$BUMP_KUBEADM"
sudo apt-mark hold kubelet kubectl
