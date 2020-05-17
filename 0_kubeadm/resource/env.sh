KUBEADM_VERSION="1.17.5-00"
# WARN 1.15.7 seems bugged w.r.t psp

# Use:
# apt-cache madison kubeadm
LATEST_KUBEADM="1.18.2-00"
LATEST_K8S="v1.18.2"

# LATEST_KUBEADM="1.16.4-00"
# LATEST_K8S="v1.16.4"

# Remove debconf messages
export TERM="linux"
