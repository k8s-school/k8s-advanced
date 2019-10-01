#!/bin/sh

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)
. "$DIR/env.sh"

apt-get update -q

# kubeadm
##
apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
sudo cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update -q
apt-get install -y --allow-downgrades --allow-change-held-packages \
    kubelet="$KUBEADM_VERSION" kubeadm="$KUBEADM_VERSION" kubectl="$KUBEADM_VERSION"
apt-mark hold kubelet kubeadm kubectl

apt-get install -y ipvsadm

# containerd
##

## Pre-requisites
cat > /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Setup required sysctl params, these persist across reboots.
cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

## Set up the repository
### Install packages to allow apt to use a repository over HTTPS
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

### Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

### Add Docker apt repository.
add-apt-repository \
	    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
	    $(lsb_release -cs) \
            stable"

## Install containerd
apt-get update && apt-get install -y containerd.io

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Restart containerd
systemctl restart containerd

# Configure crictl client
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF

# Calico
#
curl -O -L  https://github.com/projectcalico/calicoctl/releases/download/v3.7.2/calicoctl
mv calicoctl /usr/local/bin
chmod +x /usr/local/bin/calicoctl

# Helm
#
HELM_VERSION=2.14.3
wget -O /tmp/helm.tgz \
https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-linux-amd64.tar.gz
cd /tmp
tar zxvf /tmp/helm.tgz
chmod +x /tmp/linux-amd64/helm
mv /tmp/linux-amd64/helm /usr/local/bin/helm-${HELM_VERSION}
ln -sf /usr/local/bin/helm-${HELM_VERSION} /usr/local/bin/helm
