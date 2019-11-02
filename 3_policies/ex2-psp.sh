#!/bin/sh

set -e
set -x

# Run on kubeadm cluster
# see "kubernetes in action" p390

# See https://kubernetes.io/docs/concepts/policy/pod-security-policy/#run-another-pod

kubectl delete ns,psp -l "policies=psp"

kubectl create namespace psp-example
kubectl label ns psp-example "policies=psp"
kubectl create serviceaccount -n psp-example fake-user
kubectl create rolebinding -n psp-example fake-editor --clusterrole=edit --serviceaccount=psp-example:fake-user

alias kubectl-admin='kubectl -n psp-example'
alias kubectl-user='kubectl --as=system:serviceaccount:psp-example:fake-user -n psp-example'

kubectl-admin apply -f https://raw.githubusercontent.com/kubernetes/website/master/content/en/examples/policy/example-psp.yaml
kubectl label psp example "policies=psp"

cat <<EOF > /tmp/pause.yaml
apiVersion: v1
kind: Pod
metadata:
  name:      pause
spec:
  containers:
    - name:  pause
      image: k8s.gcr.io/pause
EOF

kubectl-user create -f /tmp/pause.yaml && >&2 echo "ERROR this command should have failed"

kubectl-user auth can-i use podsecuritypolicy/example && >&2 echo "ERROR this command should have failed"

kubectl-admin create role psp:unprivileged \
    --verb=use \
    --resource=podsecuritypolicy \
    --resource-name=example

kubectl-admin create rolebinding fake-user:psp:unprivileged \
    --role=psp:unprivileged \
    --serviceaccount=psp-example:fake-user

kubectl-user auth can-i use podsecuritypolicy/example

kubectl-user create -f /tmp/pause.yaml

cat <<EOF > /tmp/priv-pause.yaml
apiVersion: v1
kind: Pod
metadata:
  name:      privileged
spec:
  containers:
    - name:  pause
      image: k8s.gcr.io/pause
      securityContext:
        privileged: true
EOF

kubectl-user create -f /tmp/priv-pause.yaml && >&2 echo "ERROR this command should have failed"

kubectl-user delete pod pause

kubectl-user create deployment pause --image=k8s.gcr.io/pause
kubectl-user get pods
kubectl-user get events | head -n 2
kubectl-admin create rolebinding default:psp:unprivileged \
    --role=psp:unprivileged \
    --serviceaccount=psp-example:default
kubectl wait --for=condition=Ready pods -l app=pause -n psp-example
kubectl-user get pods