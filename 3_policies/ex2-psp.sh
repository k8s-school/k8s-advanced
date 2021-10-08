#!/bin/sh

DIR=$(cd "$(dirname "$0")"; pwd -P)

set -eux

# Run on kubeadm cluster
# see "kubernetes in action" p390

# Delete psp 'restricted', installed during kind install, so that fake use can not create pod
kubectl delete psp -l restricted

# See https://kubernetes.io/docs/concepts/policy/pod-security-policy/#run-another-pod
kubectl delete namespace,psp -l "policies=psp"
kubectl delete psp default || echo "OK: No default psp, from psp-advanced" 

kubectl create namespace psp-example
kubectl label ns psp-example "policies=psp"
kubectl create serviceaccount -n psp-example fake-user

# Allow fake-user to create pods
kubectl create rolebinding -n psp-example fake-editor --clusterrole=edit --serviceaccount=psp-example:fake-user

alias kubectl-admin='kubectl -n psp-example'
alias kubectl-user='kubectl --as=system:serviceaccount:psp-example:fake-user -n psp-example'

kubectl apply -f https://raw.githubusercontent.com/kubernetes/website/master/content/en/examples/policy/example-psp.yaml
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

if kubectl-user create -f /tmp/pause.yaml
then
    >&2 echo "ERROR: User 'fake-user' should not be able to create pod"
else
    >&2 echo "EXPECTED ERROR: User 'fake-user' cannot create pod"
fi

kubectl-user auth can-i use podsecuritypolicy/example ||
    >&2 echo "EXPECTED ERROR"

# kubectl-admin create role psp:unprivileged \
#    --verb=use \
#    --resource=podsecuritypolicy \
#    --resource-name=example

kubectl apply -n psp-example -f "$DIR"/resource/role-use-psp.yaml 

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

kubectl-user create -f /tmp/priv-pause.yaml ||
    >&2 echo "EXPECTED ERROR: User 'fake-user' cannot create privileged container"

kubectl-user delete pod pause

kubectl-user create deployment pause --image=k8s.gcr.io/pause
kubectl-user get pods
kubectl-user get events | head -n 2
kubectl-admin create rolebinding default:psp:unprivileged \
    --role=psp:unprivileged \
    --serviceaccount=psp-example:default
# Wait for deployment to recreate the pod
sleep 5
kubectl wait --timeout=60s --for=condition=Ready pods -l app=pause -n psp-example
kubectl-user get pods
