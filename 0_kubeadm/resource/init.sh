#!/bin/bash

set -euxo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)

usage() {
    cat << EOD

Initialize k8s master with kubeadm

Usage: $(basename "$0") [options]
Available options:
  -h            This message

Init k8s master

EOD
}

# Get the options
while getopts h c ; do
    case $c in
        h) usage ; exit 0 ;;
        \?) usage ; exit 2 ;;
    esac
done
shift "$((OPTIND-1))"

if [ $# -ne 0 ] ; then
    usage
    exit 2
fi

# Move token file to k8s master
TOKEN_DIR=/etc/kubernetes/auth
sudo mkdir -p $TOKEN_DIR
sudo chmod 600 $TOKEN_DIR
sudo cp -f "$DIR/tokens.csv" $TOKEN_DIR

sudo mkdir -p /etc/kubeadm
sudo cp -f $DIR/kubeadm-config*.yaml /etc/kubeadm

if [ ! -d "$HOME/k8s-advanced" ]
then
    git clone https://github.com/k8s-school/k8s-advanced.git  $HOME/k8s-advanced
else
    cd "$HOME/k8s-advanced"
    git pull
fi

KUBEADM_CONFIG="/etc/kubeadm/kubeadm-config.yaml"

# Init cluster using configuration file
sudo kubeadm init --config="$KUBEADM_CONFIG"

# Manage kubeconfig
mkdir -p $HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Enable auto-completion
echo 'source <(kubectl completion bash)' >> ~/.bashrc

# Install CNI plugin
# See https://projectcalico.docs.tigera.io/getting-started/kubernetes/quickstart
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.5/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.5/manifests/custom-resources.yaml

kubectl wait --for=condition=ready --timeout=-1s nodes $(hostname) 

# Update kubeconfig with users alice and bob
USER=alice
kubectl config set-credentials "$USER" --token=02b50b05283e98dd0fd71db496ef01e8
kubectl config set-context $USER --cluster=kubernetes --user=$USER

USER=bob
kubectl config set-credentials "$USER" --token=492f5cd80d11c00e91f45a0a5b963bb6
kubectl config set-context $USER --cluster=kubernetes --user=$USER
