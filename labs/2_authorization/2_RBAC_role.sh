#!/bin/sh

set -e
set -x

# RBAC
# see "kubernetes in action" p357

DIR=$(cd "$(dirname "$0")"; pwd -P)

. $DIR/../conf.version.sh

# Delete all namespaces with label 'RBAC=role' to make current script idempotent
kubectl delete ns -l RBAC=role

# Create namespaces 'foo' and 'bar' and add label "RBAC=role"
kubectl create ns foo
kubectl create ns bar
kubectl label ns foo bar "RBAC=role"

ink "Create a deployment and its related service in ns 'foo'"
# for example use image gcr.io/kuar-demo/kuard-amd64:green
kubectl create deployment kuard --image=gcr.io/kuar-demo/kuard-amd64:green -n foo
kubectl expose deployment kuard -n foo --type=NodePort --port=8080 --name=kuard-service

ink "Create pod using image 'k8sschool/kubectl-proxy', and named 'shell' in ns 'bar'"
kubectl run shell --image=k8sschool/kubectl-proxy:$KUBECTL_PROXY_VERSION -n bar

ink "Wait for pod bar:shell to be in running state"
kubectl wait -n bar --for=condition=Ready pods shell

ink "Access svc 'foo:kuard-service' from pod 'bar:shell'"
while ! kubectl exec -it -n bar shell -- curl --connect-timeout 2 http://kuard-service.foo:8080
do
    ink "Waiting for kuard svc"
    sleep 2
done
ink "Set the namespace preference to 'foo'"
ink "so that all kubectl command are ran in ns 'foo' by default"
kubectl config set-context $(kubectl config current-context) --namespace=foo

ink "Create pod using image 'k8sschool/kubectl-proxy', and named 'shell' in ns 'foo'"
kubectl run shell --image=k8sschool/kubectl-proxy:$KUBECTL_PROXY_VERSION

# Wait for foo:shell to be in running state
kubectl  wait --for=condition=Ready pods shell

# Check RBAC is enabled:
# inside foo:shell, curl k8s api server
# at URL <API_SERVER>:<PORT>/api/v1/namespaces/foo/services
kubectl exec -it shell -- curl localhost:8001/api/v1/namespaces/foo/services

# Study and create role manifest/service-reader.yaml in ns 'foo'
kubectl apply -f "$DIR/manifest/service-reader.yaml"

# Create role service-reader.yaml in ns 'bar'
# Use 'kubectl create role' command instead of yaml
kubectl create role service-reader --verb=get --verb=list --resource=services -n bar

# Create a rolebindind 'service-reader-rb' to bind role foo:service-reader
# to sa (i.e. serviceaccount) foo:default
kubectl create rolebinding service-reader-rb --role=service-reader --serviceaccount=foo:default

# List service in ns 'foo' from foo:shell
kubectl exec -it -n foo shell -- curl localhost:8001/api/v1/namespaces/foo/services

# List service in ns 'foo' from bar:shell
kubectl exec -it -n bar shell -- curl localhost:8001/api/v1/namespaces/foo/services

# Use the patch command, and jsonpatch syntax to add bind foo:service-reader to sa bar.default
# See http://jsonpatch.com for examples
kubectl patch rolebindings.rbac.authorization.k8s.io -n foo service-reader-rb --type='json' \
    -p='[{"op": "add", "path": "/subjects/-", "value": {"kind": "ServiceAccount","name": "default","namespace": "bar"} }]'

# List service in ns 'foo' from bar:shell
kubectl exec -it -n bar shell -- curl localhost:8001/api/v1/namespaces/foo/services
