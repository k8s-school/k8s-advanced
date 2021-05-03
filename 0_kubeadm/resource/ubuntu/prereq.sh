#!/bin/bash

set -euxo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)
. "$DIR/../env.sh"

sudo apt-get update -q

cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Setup required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

# Install containerd
## Set up the repository
### Install packages to allow apt to use a repository over HTTPS
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

### Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --no-tty --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

### Add Docker apt repository.
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

## Install containerd
sudo apt-get update -q
sudo apt-get install -y containerd.io

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Restart containerd
sudo systemctl restart containerd

# kubeadm
##
sudo apt-get update 
sudo apt-get install -y apt-transport-https ca-certificates curl
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
apt-get install -y --allow-downgrades --allow-change-held-packages \
    kubelet="$KUBEADM_VERSION" kubeadm="$KUBEADM_VERSION" kubectl="$KUBEADM_VERSION"
sudo apt-mark hold kubelet kubeadm kubectl


sudo apt-get install -y ipvsadm

# Configure crictl client
sudo cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF

# Helm
#
HELM_VERSION=3.5.4
wget -O /tmp/helm.tgz https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
cd /tmp
tar zxvf /tmp/helm.tgz
rm /tmp/helm.tgz
chmod +x /tmp/linux-amd64/helm
mv /tmp/linux-amd64/helm /usr/local/bin/helm

