KUBEADM_VERSION="1.14.6-00"

DOCKER_VERSION="18.09.7-0ubuntu1~18.04.4"

# Get latest kubeadm version
sudo apt-get update -q
LATEST_KUBEADM=$(apt-cache madison kubeadm | head -n 1 | cut -d'|' -f2 | xargs)

LATEST_K8S="v1.15.3"

# Remove debconf messages
export TERM="linux"
