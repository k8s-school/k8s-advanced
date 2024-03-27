# Pre-requisites

Get 3 or 4 GCE instances

# Upgrade using kubeadm file

```shell
sudo kubeadm upgrade apply --config /etc/kubeadm/kubeadm-config.yaml
```

# Set up access to gce instances

```shell
# It will not work with kubectl for api-server access
#because of SSL certs (localhost is not recognized)
# but it can be used with a 'port-forward' to a pod
NODE=clus0-0
gcloud compute ssh  --ssh-flag="-L 3000:localhost:3000" "$NODE"

# It will not work with kubectl for api-server access
# because of SSL certs (external and internal address for instance are different
gcloud compute firewall-rules create apiserver --allow tcp:6443
mkdir -p $HOME/.kube
gcloud compute scp $NODE:~/.kube/config $HOME/.kube/config
```