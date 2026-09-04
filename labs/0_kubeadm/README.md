# Lab: install Kubernetes with kubeadm

Build a two-node Kubernetes cluster by hand with `kubeadm`. This is the only lab
of the course that does not run on `kind`: a control plane installed from
scratch needs real machines.

The walkthrough is published at
<https://k8s-school.fr/labs/k8s/en/1_labs/kubeadm/>; the scripts here automate
the same steps.

## Pre-requisites

Two VMs, already provisioned for you:

| Host | Role |
|---|---|
| `student<ID>-1` | master (control plane) |
| `student<ID>-2` | worker |

`<ID>` is the number of your training account: logged in as `student3`, your
nodes are `student3-1` and `student3-2`. Both names resolve from your training
account with no setup — the ssh config and the key were installed for you:

```shell
ssh student3-1     # or simply: ssh "$USER-1"
```

The nodes run Ubuntu 24.04 with passwordless `sudo` for the `ubuntu` account,
and nothing else: installing containerd, kubeadm and the CNI plugin is the
exercise.

Trainers: the VMs come from `make cluster nb=<N>` in
[k8s-server](https://github.com/k8s-school/k8s-server)`/provisioning`, which
also documents the teardown.

## Create the cluster

`env.sh` derives `MASTER` and `NODES` from your login, so there is nothing to
edit:

```shell
./create.sh
```

It copies `resource/` to both nodes, installs the pre-requisites, runs
`kubeadm init` on the master with `resource/kubeadm-config.yaml`, installs
Cilium, and joins the worker.

Check the result from the master:

```shell
ssh "$USER-1"
kubectl get nodes
kubectl cluster-info
```

Run it as another participant — as a trainer, say — by overriding `STUDENT`:

```shell
STUDENT=student1 ./create.sh
```

## Reach the API server from your workstation

The certificate the API server presents is issued for its internal address, so
`kubectl` from outside will not validate it. Work from the master instead, or
forward a port for a specific service:

```shell
ssh -L 3000:localhost:3000 "$USER-1"
```

## Upgrade the cluster

Rolling upgrade to `BUMP_K8S` / `BUMP_KUBEADM`, both set in `resource/env.sh`:

```shell
./upgrade.sh
```

Upgrading straight from the kubeadm config file:

```shell
sudo kubeadm upgrade apply --config /etc/kubeadm/kubeadm-config.yaml
```

## Start over

```shell
./reset.sh      # kubeadm reset on every node, cluster gone, VMs kept
./create.sh
```

If a node is beyond repair, ask your trainer to rebuild it: destroying and
recreating the VMs is quicker than unpicking a half-installed control plane.
