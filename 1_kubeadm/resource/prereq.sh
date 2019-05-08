#!/bin/sh

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)
. "$DIR/env.sh"

apt-get update -q
apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
sudo cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update -q
apt-get install -y --allow-downgrades --allow-change-held-packages \
    kubelet="$KUBEADM_VERSION" kubeadm="$KUBEADM_VERSION" kubectl="$KUBEADM_VERSION"
apt-mark hold kubelet kubeadm kubectl
apt-get install -y docker.io="$DOCKER_VERSION" ipvsadm
apt-get -y autoremove

systemctl enable docker.service

curl -O -L  https://github.com/projectcalico/calicoctl/releases/download/v3.7.2/calicoctl
mv calicoctl /usr/local/bin
chmod +x /usr/local/bin/calicoctl

HELM_VERSION=2.13.1
wget -O /tmp/helm.tgz \
https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-linux-amd64.tar.gz
cd /tmp
tar zxvf /tmp/helm.tgz
chmod +x /tmp/linux-amd64/helm
mv /tmp/linux-amd64/helm /usr/local/bin/helm-${HELM_VERSION}
ln -sf /usr/local/bin/helm-${HELM_VERSION} /usr/local/bin/helm
