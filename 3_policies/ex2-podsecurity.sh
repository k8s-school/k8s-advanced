#!/bin/bash

set -euxo pipefail
shopt -s expand_aliases

readonly DIR=$(cd "$(dirname "$0")"; pwd -P)

# See https://kubernetes.io/blog/2021/12/09/pod-security-admission-beta/#hands-on-demo for details

kubectl delete namespace -l "podsecurity=enabled"
NS="verify-pod-security"

echo "Confirm Pod Security is enabled v1"
# TODO Add a PR to k8s blog to remove -i option
kubectl -n kube-system exec kube-apiserver-kind-control-plane -t -- kube-apiserver -h | grep "default enabled plugins" | grep "PodSecurity"


echo "Confirm Pod Security is enabled v2"
kubectl create namespace "$NS"
kubectl label ns "$NS" "podsecurity=enabled"
kubectl label namespace "$NS" pod-security.kubernetes.io/enforce=restricted
# The following command does NOT create a workload (--dry-run=server)
kubectl -n "$NS" run test --dry-run=server --image=busybox --privileged || >&2 echo "EXPECTED ERROR"
kubectl delete namespace "$NS"

kubectl create namespace "$NS"
kubectl label ns "$NS" "podsecurity=enabled"

echo "Enforces a \"restricted\" security policy and audits on restricted"
kubectl label --overwrite ns verify-pod-security \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted

# Next, try to deploy a privileged workload in the namespace.
if cat <<EOF | kubectl -n verify-pod-security apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: busybox-privileged
spec:
  containers:
  - name: busybox
    image: busybox
    args:
    - sleep
    - "1000000"
    securityContext:
      allowPrivilegeEscalation: true
EOF
then
    >&2 echo "ERROR: Should not be able to create privileged pod in namespace $NS"
    exit 1
else
    >&2 echo "EXPECTED ERROR: No able to create privileged pod in namespace $NS"
fi

echo "Enforces a \"privileged\" security policy and warns / audits on baseline"
kubectl label --overwrite ns verify-pod-security \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=baseline \
  pod-security.kubernetes.io/audit=baseline

# Next, try to deploy a privileged workload in the namespace.
cat <<EOF | kubectl -n verify-pod-security apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: busybox-privileged
spec:
  containers:
  - name: busybox
    image: busybox
    args:
    - sleep
    - "1000000"
    securityContext:
      allowPrivilegeEscalation: true
EOF
alias kubectl-admin="kubectl -n $NS"

kubectl-admin get pods
kubectl-admin delete pod busybox-privileged

# Baseline level and workload
# The baseline policy demonstrates sensible defaults while preventing common container exploits.

echo "Enforces a \"restricted\" security policy and audits on restricted"
kubectl label --overwrite ns verify-pod-security \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted

# Apply the workload.

if cat <<EOF | kubectl -n verify-pod-security apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: busybox-baseline
spec:
  containers:
  - name: busybox
    image: busybox
    args:
    - sleep
    - "1000000"
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        add:
          - NET_BIND_SERVICE
          - CHOWN
EOF
then
    >&2 echo "ERROR: Should not be able to create privileged pod in namespace $NS"
    exit 1
else
    >&2 echo "EXPECTED ERROR: No able to create privileged pod in namespace $NS"
fi

# Let's apply the baseline Pod Security level and try again.
echo "Enforces a \"baseline\" security policy and warns / audits on restricted"
kubectl label --overwrite ns verify-pod-security \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted

if cat <<EOF | kubectl -n verify-pod-security apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: busybox-baseline
spec:
  containers:
  - name: busybox
    image: busybox
    args:
    - sleep
    - "1000000"
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        add:
          - NET_BIND_SERVICE
          - CHOWN
EOF
then
    echo "Create privileged pod in namespace $NS"
else
    >&2 echo "ERROR: No able to create privileged pod in namespace $NS"
    exit 1
fi

kubectl -n "$NS" delete pod busybox-baseline

# Restricted level and workload

echo "Enforces a \"restricted\" security policy and audits on restricted"
kubectl label --overwrite ns verify-pod-security \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted

if cat <<EOF | kubectl -n "$NS" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: busybox-baseline
spec:
  containers:
  - name: busybox
    image: busybox
    args:
    - sleep
    - "1000000"
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        add:
          - NET_BIND_SERVICE
          - CHOWN
EOF
then
    >&2 echo "ERROR: Should not be able to create privileged pod in namespace $NS"
    exit 1
else
    >&2 echo "EXPECTED ERROR: No able to create privileged pod in namespace $NS"
fi

if cat <<EOF | kubectl -n "$NS" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: busybox-restricted
spec:
  securityContext:
    runAsUser: 65534
  containers:
  - name: busybox
    image: busybox
    args:
    - sleep
    - "1000000"
    securityContext:
      seccompProfile:
        type: RuntimeDefault
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
        add:
          - NET_BIND_SERVICE
EOF
then
    echo "Create pod in namespace $NS"
else
    >&2 echo "ERROR: No able to create pod in namespace $NS"
    exit 1
fi

echo "Use 'crictl inspect' to check pods on nodes"



