# Exercise: build a Kubernetes cluster with kubeadm

Install a two-node Kubernetes cluster by hand. This is the only lab of the
course that does not run on `kind`: a control plane installed from scratch
needs real machines.

Budget about an hour. Work through it yourself before looking at the solution
at the end — the point is to see what `kind` and the managed offerings do for
you.

## Your machines

Two Ubuntu 24.04 VMs are already provisioned for you:

| Host | Role |
|---|---|
| `student<ID>-1` | master (control plane) |
| `student<ID>-2` | worker |

`<ID>` is the number of your training account. Logged in as `student3`, your
nodes are `student3-1` and `student3-2`. Both names resolve from your training
account with nothing to set up:

```shell
ssh student3-1     # or simply: ssh "$USER-1"
```

The `ubuntu` account has passwordless `sudo`, and the machines carry nothing
else: installing the container runtime and Kubernetes is the exercise.

## What to do

The reference walkthrough is <https://k8s-school.fr/labs/k8s/en/1_labs/kubeadm/>.
Follow it, and stop at each step to ask yourself what it is for.

1. **Install containerd — on both nodes.** Load the `overlay` and `br_netfilter`
   kernel modules, set the sysctl parameters, then install and configure
   containerd with the `systemd` cgroup driver.
2. **Install kubeadm, kubelet and kubectl — on both nodes.** Pin them with
   `apt-mark hold` so a routine `apt-get upgrade` cannot move your cluster to a
   version you did not choose.
3. **Initialise the control plane — on the master only**, with `kubeadm init`.
   Read its output carefully: it hands you the three things you need next.
4. **Configure `kubectl`** for your regular account (not `root`).
5. **Install a CNI plugin** — Cilium here. Look at `kubectl get nodes` before
   and after: the node stays `NotReady` until a network plugin is running.
6. **Join the worker** with the `kubeadm join` command printed by `kubeadm init`.
   The token expires, so if you took a break, print a fresh one with
   `kubeadm token create --print-join-command`.

## Check your work

From the master:

```shell
kubectl get nodes            # both nodes, both Ready
kubectl cluster-info
kubectl get pods -n kube-system -o wide
```

## Questions to think about

- Why does the master report `NotReady` between step 3 and step 5?
- Which containers make up the control plane, and where are their manifests
  on the master? (`/etc/kubernetes/manifests` — who reads that directory?)
- `kubeadm init` printed a token and a CA certificate hash. What does each one
  protect against?
- The `kubelet` runs on the master too. Why, when no user workload is scheduled
  there?

## Starting over

A cluster in a state you cannot explain is not worth debugging during a lab:

```shell
cd labs/0_kubeadm
./reset.sh
```

## Solution

`create.sh` in this directory automates the whole exercise — the same steps,
run over SSH on both nodes:

```shell
cd labs/0_kubeadm
./create.sh
```

Read `resource/ubuntu/prereq.sh` and `resource/init.sh`: they are the solution
to steps 1-2 and 3-5 respectively. Note that `init.sh` goes slightly further
than the walkthrough, passing a `kubeadm-config.yaml` that enables admission
plugins and a static token file — those serve the RBAC and policy labs that
come next.
