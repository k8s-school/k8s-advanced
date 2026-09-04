# Set-up platform

## Pre-requisite

The two nodes of the kubeadm lab, `student<ID>-1` (master) and `student<ID>-2`
(worker). See `../0_kubeadm/README.md`.

## Create an up and running k8s cluster

```shell
WORKDIR="../0_kubeadm"
"$WORKDIR"/create.sh
```
