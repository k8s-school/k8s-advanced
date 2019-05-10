# Pre-requisites

Get 3 or 4 GCE instances

# Upgrade using kubeadm file

```shell
sudo kubeadm upgrade apply --config /etc/kubeadm/kubeadm-config.yaml
```

# Set up tunnel for gce instance

```shell
gcloud compute ssh example-instance \
    --project my-project \
    --zone us-central1-a \
    -- -L 2222:localhost:8888
```