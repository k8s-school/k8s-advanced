#!/bin/bash

# See https://github.com/NorfairKing/autorecorder

set -euxo pipefail

# Install rbac-tool
curl https://raw.githubusercontent.com/alcideio/rbac-tool/master/download.sh | bash

# Add rbac-tool to PATH
export PATH=$PWD/bin:$PATH

# Generate bash completion
source <(rbac-tool bash-completion)

# Analyze RBAC permissions of the cluster pointed by current context
rbac-tool analysis | less

# Get ClusterRole used by ServiceAccount system:serviceaccount:kube-system:replicaset-controller
# Use regex to match service account name
rbac-tool lookup -e ".*replicaset.*"

# List Policy Rules For ServiceAccount replicaset-controller
# It can create and delete Pods and update replicasets, this is consistent
rbac-tool policy-rules -e "replicaset-controller"

# Shows which subjects (user/group/serviceaccount) have RBAC permissions to perform an action
rbac-tool who-can create pods

