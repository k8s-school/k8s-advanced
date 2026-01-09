#!/bin/bash

set -euxo pipefail

MASTER_NODE=$(kubectl get nodes '--selector=node-role.kubernetes.io/master' -o jsonpath='{.items[0].metadata.name}')

docker exec -t -- kind-control-plane sh -c 'ps -ef | grep "/usr/bin/kubelet"'
docker exec -t -- kind-control-plane sh -c 'cat /var/lib/kubelet/config.yaml | grep -i staticPodPath'
docker exec -t -- kind-control-plane sh -c 'ls /etc/kubernetes/manifests'
