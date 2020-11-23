#!/bin/sh

# Create an up and running k8s cluster

set -e
set -x

usage() {
    cat << EOD
Usage: $(basename "$0") [options]
Available options:
  -p            Add support for policies (psp+network)
  -h            This message

Init k8s master

EOD
}

POLICY_OPT=""

# Get the options
while getopts hp c ; do
    case $c in
        p) POLICY_OPT="-p" ;;
        h) usage ; exit 0 ;;
        \?) usage ; exit 2 ;;
    esac
done
shift "$((OPTIND-1))"

if [ $# -ne 0 ] ; then
    usage
    exit 2
fi

DIR=$(cd "$(dirname "$0")"; pwd -P)

. "$DIR/env.sh"

echo "Copy scripts to all nodes"
echo "-------------------------"
parallel --tag -- $SCP --recurse "$DIR/resource" $USER@{}:/tmp ::: "$MASTER" $NODES

echo "Install prerequisites"
echo "---------------------"
parallel -vvv --tag -- "gcloud compute ssh $USER@{} -- sudo sh /tmp/resource/$DISTRIB/prereq.sh" ::: "$MASTER" $NODES

echo "Initialize master"
echo "-----------------"
$SSH "$USER@$MASTER" -- sh /tmp/resource/init.sh "$POLICY_OPT"

echo "Join nodes"
echo "----------"
# TODO test '-ttl' option
JOIN_CMD=$($SSH "$USER@$MASTER" -- 'sudo kubeadm token create --print-join-command')
# Remove trailing carriage return
JOIN_CMD=$(echo "$JOIN_CMD" | grep 'kubeadm join' | sed -e 's/[\r\n]//g')
echo "Join command: $JOIN_CMD"
parallel -vvv --tag -- "$SSH $USER@{} -- sudo '$JOIN_CMD'" ::: $NODES
