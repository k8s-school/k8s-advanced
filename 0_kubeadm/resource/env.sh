KUBEADM_VERSION="1.14.6-00"

DOCKER_VERSION="18.09.7-0ubuntu1~18.04.4"

# Get latest kubeadm version
sudo apt-get update -q

# Use:
# apt-cache madison kubeadm
LATEST_KUBEADM="1.15.4-00"
LATEST_K8S="v1.15.4"

# Remove debconf messages
export TERM="linux"
