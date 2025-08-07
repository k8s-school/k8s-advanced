#!/bin/sh

# Reset a k8s cluster an all nodes

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)
. "$DIR/env.sh"

echo "Reset all nodes"
echo "---------------"
parallel -vvv --tag -- "$SSH {} -- sh /tmp/resource/reset.sh" ::: $NODES
$SSH "$USER@$MASTER" -- sh /tmp/resource/reset.sh "$MASTER" 

