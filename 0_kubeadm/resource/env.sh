KUBEADM_VERSION="1.14.10-00"
# WARN 1.15.7 seems bugged w.r.t psp

# Use:
# apt-cache madison kubeadm
LATEST_KUBEADM="1.15.7-00"
LATEST_K8S="v1.15.7"

# LATEST_KUBEADM="1.16.4-00"
# LATEST_K8S="v1.16.4"

# Remove debconf messages
export TERM="linux"
