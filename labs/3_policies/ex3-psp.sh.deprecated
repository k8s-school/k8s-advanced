#!/bin/sh

set -e
set -x

DIR=$(cd "$(dirname "$0")"; pwd -P)

# Run on kubeadm cluster
# see "kubernetes in action" p391

# Delete psp 'restricted', installed during kind install, so that fake use can not create pod
kubectl delete psp -l restricted

NS="psp-advanced"

kubectl delete ns,psp,clusterrolebindings -l "policies=$NS"

kubectl create namespace "$NS"
kubectl label ns "$NS" "policies=$NS"

KUBIA_DIR="/tmp/kubernetes-in-action"
if [ ! -d "$KUBIA_DIR" ]; then
    git clone https://github.com/k8s-school/kubernetes-in-action.git /tmp/kubernetes-in-action

fi

# Exercice: define default policy
kubectl apply -f $DIR/../0_kubeadm/resource/psp/default-psp-with-rbac.yaml

# Exercice: enable alice to create pod
kubectl create rolebinding alice:edit \
    --clusterrole=edit \
    --user=alice \
    --namespace "$NS"

# Check
alias kubectl-user="kubectl --as=alice --namespace '$NS'"

kubectl-user run --restart=Never -it ubuntu --image=ubuntu id

# Remark: cluster-admin has access to all psp (see cluster-admin role), and use the most permissive in each section

cd "$KUBIA_DIR"/Chapter13

# 13.3.1 Introducing the PodSecurityPolicy resource
kubectl apply -f "$DIR"/resource/pod-security-policy.yaml
kubectl-user create --namespace "$NS" -f pod-privileged.yaml ||
    >&2 echo "EXPECTED ERROR: User 'alice' cannot create privileged pod"

# 13.3.2 Understanding runAsUser, fsGroup, and supplementalGroups
# policies
kubectl apply -f "$DIR"/resource/psp-must-run-as.yaml
# DEPLOYING A POD WITH RUN_AS USER OUTSIDE OF THE POLICY’S RANGE
kubectl-user create --namespace "$NS" -f pod-as-user-guest.yaml ||
    >&2 echo "EXPECTED ERROR: Cannot deploy a pod with 'run_as user' outside of the policy’s range"
# DEPLOYING A POD WITH A CONTAINER IMAGE WITH AN OUT-OF-RANGE USER ID
kubectl-user run --restart=Never --namespace "$NS" run-as-5 --image luksa/kubia-run-as-user-5 --restart Never
kubectl wait --timeout=60s -n "$NS" --for=condition=Ready pods run-as-5
kubectl exec --namespace "$NS" run-as-5 -- id

kubectl apply -f "$DIR"/resource/psp-capabilities.yaml
kubectl-user create -f pod-add-sysadmin-capability.yaml ||
    >&2 echo "EXPECTED ERROR: Cannot deploy a pod with capability 'sysadmin'"
kubectl apply -f "$DIR"/resource/psp-volumes.yaml

# 13.3.5 Assigning different PodSecurityPolicies to different users
# and groups
# Enable bob to create pod
kubectl create rolebinding bob:edit \
    --clusterrole=edit \
    --user=bob\
    --namespace "$NS"
# WARN: book says 'psp-privileged', p.398
kubectl create clusterrolebinding psp-bob --clusterrole=psp:privileged --user=bob
kubectl label clusterrolebindings psp-bob "policies=$NS"

# --as is usable even if user does not exist, this does not apply for -- user
kubectl --namespace "$NS" --as alice create -f pod-privileged.yaml ||
    >&2 echo "EXPECTED ERROR: User 'alice' cannot create a privileged pod"
kubectl --namespace "$NS" --as bob create -f pod-privileged.yaml
