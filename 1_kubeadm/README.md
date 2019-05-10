# Pre-requisites

Get 3 or 4 GCE instances

# Upgrade using kubeadm file

```shell
sudo kubeadm upgrade apply --config /etc/kubeadm/kubeadm-config.yaml
```

# Set up tunnel for gce instance

```shell
# It will not work because of SSL certs (localhost is not recognized)
NODE=clus0-0
ssh $NODE \
    -L 6443:localhost:6443
```