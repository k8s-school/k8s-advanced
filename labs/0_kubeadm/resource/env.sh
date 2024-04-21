K8S_VERSION="v1.29"
KUBEADM_VERSION="1.29.3-1.1"

# Current version
# KUBEADM_VERSION="1.25.2-00"
# Use:
# apt-cache madison kubeadm

# Required for update procedure
BUMP_KUBEADM="1.29.4-2.1"
BUMP_K8S="v1.29.4"

# Remove debconf messages
export TERM="linux"
