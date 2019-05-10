toto#!/bin/sh

set -e
set -x

# Run on kubeadm cluster
# see "kubernetes in action" p391

KUBIA_DIR="/tmp/kubernetes-in-action"
if [ ! -d "$KUBIA_DIR" ]; then
    git clone https://github.com/luksa/kubernetes-in-action.git /tmp/kubernetes-in-action

fi

# Exercice: define default policy
kubectl apply -f /tmp/resource/psp/default-psp-with-rbac.yaml

# Exercice: enable alice to create pod
kubectl create rolebinding alice:edit \
    --clusterrole=edit \
    --user=alice

# Check
alias kubectl-user='kubectl --as=alice'
kubectl-user run --generator=run-pod/v1 -it ubuntu --image=ubuntu id

# Remark: cluster-admin has access to all psp (see cluster-admin role), and use the most permissive in each section

cd "$KUBIA_DIR"/Chapter13

# 13.3.1 Introducing the PodSecurityPolicy resource
kubectl apply -f pod-security-policy.yaml
kubectl-user create -f pod-privileged.yaml && >&2 echo "ERROR this command should have failed"

# 13.3.2 Understanding runAsUser, fsGroup, and supplementalGroups
# policies
kubectl apply -f psp-must-run-as.yaml
# DEPLOYING A POD WITH RUN_AS USER OUTSIDE OF THE POLICY’S RANGE
kubectl-user create -f pod-as-user-guest.yaml && >&2 echo "ERROR this command should have failed"
# DEPLOYING A POD WITH A CONTAINER IMAGE WITH AN OUT-OF-RANGE USER ID
kubectl-user run run-as-5 --image luksa/kubia-run-as-user-5 --restart Never
sleep 5
kubectl exec run-as-5 -- id

kubectl apply -f psp-capabilities.yaml
kubectl-user create -f pod-add-sysadmin-capability.yaml
kubectl apply -f psp-volumes.yaml

# 13.3.5 Assigning different PodSecurityPolicies to different users
# and groups
# Enable bob to create pod
kubectl create rolebinding bob:edit \
    --clusterrole=edit \
    --user=bob
# WARN: book says 'psp-privileged', p.398
kubectl create clusterrolebinding psp-bob --clusterrole=privileged-psp --user=bob
kubectl --user alice create -f pod-privileged.yaml && >&2 echo "ERROR this command should have failed"
