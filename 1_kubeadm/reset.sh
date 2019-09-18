#!/bin/sh

# Reset a k8s cluster an all nodes

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)
. "$DIR/env.sh"

echo "Copy scripts to all nodes"
echo "-------------------------"
parallel --tag -- $SCP --recurse "$DIR/resource" $USER@{}:/tmp ::: "$MASTER" $NODES

echo "Reset all nodes"
echo "---------------"
parallel -vvv --tag -- "gcloud compute ssh {} -- sh /tmp/resource/reset.sh" ::: "$MASTER" $NODES

