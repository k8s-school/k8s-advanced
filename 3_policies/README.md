# Set-up platform 

## Pre-requisite

Get 3 nodes on GCP

## Create an up and running k8s cluster with PSP enabled

```shell
WORKDIR="../1_kubeadm"

. "$WORKDIR/env.sh"

"$WORKDIR"/create.sh -p
```
