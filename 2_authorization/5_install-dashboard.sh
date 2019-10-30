
#!/bin/sh

set -e
set -x

# Install dashboard and set up RBAC
# see See https://github.com/kubernetes/dashboard

DIR=$(cd "$(dirname "$0")"; pwd -P)

kubectl delete ns -l "RBAC=dashboard"

kubectl create ns kubernetes-dashboard
kubectl label ns kubernetes-dashboard "RBAC=dashboard"

kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml
kubectl apply -f "$DIR"/manifest/sa_dashboard.yaml

echo "Get token"
kubectl -n kubernetes-dashboard describe secret $(kubectl -n kubernetes-dashboard get secret | grep admin-user | awk '{print $1}')


echo "Run:\n \
$ kubectl proxy \n\
Now access Dashboard at: \n\
http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/."
