#!/bin/bash

set -euxo pipefail

# Install dashboard and set up RBAC
# see https://github.com/kubernetes/dashboard

DIR=$(cd "$(dirname "$0")"; pwd -P)

kubectl delete ns -l "RBAC=dashboard"

kubectl create ns kubernetes-dashboard
kubectl label ns kubernetes-dashboard "RBAC=dashboard"

kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0/aio/deploy/recommended.yaml 
kubectl apply -f "$DIR"/manifest/sa_dashboard.yaml

echo "Get token"
kubectl -n kubernetes-dashboard describe secret $(kubectl -n kubernetes-dashboard get secret | grep admin-user | awk '{print $1}')


echo "Run:\n \
$ kubectl proxy \n\
Now access Dashboard at: \n\
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/."
