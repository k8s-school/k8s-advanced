#!/bin/bash

# See https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/cpu-constraint-namespace/

set -euxo pipefail

kubectl delete ns -l "limitrange=true"
NS="constraints-cpu-example"
kubectl create namespace "$NS"
kubectl label ns "$NS" "limitrange=true"
 
kubectl apply -f https://k8s.io/examples/admin/resource/cpu-constraints.yaml --namespace="$NS"
kubectl get limitrange cpu-min-max-demo-lr --output=yaml --namespace="$NS"
kubectl apply -f https://k8s.io/examples/admin/resource/cpu-constraints-pod.yaml --namespace="$NS"
kubectl get pod constraints-cpu-demo --namespace="$NS"
kubectl get pod constraints-cpu-demo --output=yaml --namespace="$NS"
kubectl delete pod constraints-cpu-demo --namespace="$NS"

# Attempt to create a Pod that exceeds the maximum CPU constraint 
kubectl apply -f https://k8s.io/examples/admin/resource/cpu-constraints-pod-2.yaml --namespace="$NS" || \
    ink -y "EXPECTED ERROR: pod cpu request is below limitrange"

# Attempt to create a Pod that does not meet the minimum CPU request
kubectl apply -f https://k8s.io/examples/admin/resource/cpu-constraints-pod-3.yaml --namespace="$NS" || \
    ink -y "EXPECTED ERROR: pod cpu request is below limitrange"

# Create a Pod that does not specify any CPU request or limit 
kubectl apply -f https://k8s.io/examples/admin/resource/cpu-constraints-pod-4.yaml --namespace="$NS"
kubectl get pod constraints-cpu-demo-4 --namespace="$NS" --output=yaml

