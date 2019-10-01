#!/bin/sh

# Backup k8s
# see https://elastisys.com/2018/12/10/backup-kubernetes-how-and-why/

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)

DATE=$(date -u +%Y%m%d-%H%M%S)
BACKUP_DIR="$HOME/backup-$DATE"
mkdir -p "$BACKUP_DIR"

# Backup certificates
sudo cp -r /etc/kubernetes/pki "$BACKUP_DIR"

# Make etcd snapshot
#



rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
INSTALL_DIR="/usr/local/etcd"
if [ ! -f "$INSTALL_DIR"/etcdctl ]; then
    # Install etcdctl
    ETCD_VER=v3.4.1
    # choose either URL
    # WARN: Google does not work on 2019-09-30
    GOOGLE_URL=https://storage.googleapis.com/etcd
    GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
    DOWNLOAD_URL=${GITHUB_URL}
    sudo rm -rf "$INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"

    curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
    sudo tar xzvf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C "$INSTALL_DIR" --strip-components=1
    rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
fi

export ETCDCTL_API=3

mkdir -p "$HOME/backup"

"$INSTALL_DIR"/etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save "$HOME/backup/etcd-snapshot.db"

# Get snapshot status
"$INSTALL_DIR"/etcdctl snapshot status "$HOME/backup/etcd-snapshot.db"

# Backup kubeadm-config
sudo cp /etc/kubeadm/kubeadm-config.yaml "$BACKUP_DIR"
