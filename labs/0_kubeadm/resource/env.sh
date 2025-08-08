K8S_VERSION="v1.32"
KUBEADM_VERSION="1.32.7-1.1"

# Current version
# KUBEADM_VERSION="1.25.2-00"
# Use:
# apt-cache madison kubeadm

# Required for update procedure
BUMP_KUBEADM="1.33.3-1.1"
BUMP_K8S="v1.33.3"

# Remove debconf messages
export TERM="linux"
