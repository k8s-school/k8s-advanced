#!/bin/sh

set -e
set -x

# RBAC sa
# see "kubernetes in action" p375

# In Kubia 13.3.1 does not work on GKE
# Instead run:
# https://kubernetes.io/docs/concepts/policy/pod-security-policy/#run-another-pod
kubectl create namespace psp-example
kubectl create serviceaccount -n psp-example fake-user
kubectl create rolebinding -n psp-example fake-editor --clusterrole=edit --serviceaccount=psp-example:fake-user

alias kubectl-admin='kubectl -n psp-example'
alias kubectl-user='kubectl --as=system:serviceaccount:psp-example:fake-user -n psp-example'

kubectl-admin apply -f https://raw.githubusercontent.com/kubernetes/website/master/content/en/examples/policy/example-psp.yaml

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

if kubectl-user create -f /tmp/pause.yaml
then
    >&2 echo "ERROR this command should have failed"
fi

kubectl-user auth can-i use podsecuritypolicy/example

kubectl-admin create role psp:unprivileged \
    --verb=use \
    --resource=podsecuritypolicy \
    --resource-name=example
role "psp:unprivileged" created

kubectl-admin create rolebinding fake-user:psp:unprivileged \
    --role=psp:unprivileged \
    --serviceaccount=psp-example:fake-user
rolebinding "fake-user:psp:unprivileged" created

kubectl-user auth can-i use podsecuritypolicy/example

kubectl-user create -f /tmp/pause.yamls

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
then
    >&2 echo "ERROR this command should have failed"
fi

kubectl-user create -f /tmp/priv-pause.yaml

kubectl-user delete pod pause

kubectl-user create deployment pause --image=k8s.gcr.io/pause
kubectl-user get pods
kubectl-user get events | head -n 2
kubectl-admin create rolebinding default:psp:unprivileged \
    --role=psp:unprivileged \
    --serviceaccount=psp-example:default
kubectl-user get pods --watch
kubectl-admin delete ns psp-example

# https://docs.bitnami.com/kubernetes/how-to/secure-kubernetes-cluster-psp/
# might be interesting
