# EXERCICE KUBEADM
##################

Installer automatiquement un cluster k8s

Doc install manuelle: https://www.k8s-school.fr/resources/fr/blog/kubeadm/

Connection SSH depuis la toolbox:
ssh clusX-0
ssh clusX-1
ssh clusX-2


Zone du cluster:
clus0-0  asia-east1-c       n1-standard-2               10.140.15.225  35.229.139.210   RUNNING
clus0-1  asia-east1-c       n1-standard-2               10.140.15.227  35.201.237.31    RUNNING
clus0-2  asia-east1-c       n1-standard-2               10.140.15.226  104.199.223.107  RUNNING
clus1-0  asia-east2-c       n1-standard-2               10.170.0.55    34.96.183.117    RUNNING
clus1-1  asia-east2-c       n1-standard-2               10.170.0.57    34.92.1.180      RUNNING
clus1-2  asia-east2-c       n1-standard-2               10.170.0.56    34.92.89.8       RUNNING
clus2-0  asia-northeast1-c  n1-standard-2               10.146.0.49    34.84.172.255    RUNNING
clus2-1  asia-northeast1-c  n1-standard-2               10.146.0.48    34.84.234.214    RUNNING
clus2-2  asia-northeast1-c  n1-standard-2               10.146.0.50    34.84.252.155    RUNNING
clus3-0  asia-northeast2-c  n1-standard-2               10.174.0.44    34.97.102.250    RUNNING
clus3-1  asia-northeast2-c  n1-standard-2               10.174.0.45    34.97.223.13     RUNNING
clus3-2  asia-northeast2-c  n1-standard-2               10.174.0.43    34.97.247.194    RUNNING
clus4-0  asia-southeast1-c  n1-standard-2               10.148.0.39    34.126.77.71     RUNNING
clus4-1  asia-southeast1-c  n1-standard-2               10.148.0.38    35.197.153.195   RUNNING
clus4-2  asia-southeast1-c  n1-standard-2               10.148.0.37    34.87.110.164    RUNNING
clus5-0  europe-north1-c    n1-standard-2               10.166.0.14    35.228.255.124   RUNNING
clus5-1  europe-north1-c    n1-standard-2               10.166.0.17    35.228.2.72      RUNNING
clus5-2  europe-north1-c    n1-standard-2               10.166.0.12    35.228.138.252   RUNNING
clus6-0  europe-west1-c     n1-standard-2               10.132.0.2     35.195.219.91    RUNNING
clus6-1  europe-west1-c     n1-standard-2               10.132.15.202  34.78.58.250     RUNNING
clus6-2  europe-west1-c     n1-standard-2               10.132.15.201  34.78.86.141     RUNNING


Copier puis paramétrer ce fichier dans la toolbox, nom 'env.sh':
  # DISTRIB="centos"
  DISTRIB="ubuntu"


  MASTER="clusX-0"
  NODES="clusX-1 clusX-2"

  # USER=fabrice_jammes_clermont_in2p3_fr
  USER=k8sstudent_gmail_com

  ZONE="asia-east1-c"
  gcloud config set compute/zone $ZONE

  SCP="gcloud compute scp"
  SSH="gcloud compute ssh"

Copier puis paramétrer ce fichier dans la toolbox, nom 'create.sh:
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
parallel -vvv --tag -- "gcloud compute ssh $USER@{} -- sudo bash /tmp/resource/$DISTRIB/prereq.sh" ::: "$MASTER" $NODES

echo "Initialize master"
echo "-----------------"
$SSH "$USER@$MASTER" -- bash /tmp/resource/init.sh "$POLICY_OPT"

echo "Join nodes"
echo "----------"
# TODO test '-ttl' option
JOIN_CMD=$($SSH "$USER@$MASTER" -- 'sudo kubeadm token create --print-join-command')
# Remove trailing carriage return
JOIN_CMD=$(echo "$JOIN_CMD" | grep 'kubeadm join' | sed -e 's/[\r\n]//g')
echo "Join command: $JOIN_CMD"
parallel -vvv --tag -- "$SSH $USER@{} -- sudo '$JOIN_CMD'" ::: $NODES

Ecrire les scripts resource/prereq.sh et resource/init.sh

# Script de reset du cluster:
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
parallel -vvv --tag -- "$SSH {} -- sh /tmp/resource/reset.sh" ::: $NODES
$SSH "$USER@$MASTER" -- sh /tmp/resource/reset.sh "$MASTER" 


remote reset.sh
#!/bin/sh

# Reset k8s cluster

set -e

sudo -- kubeadm reset -f
sudo -- sh -c "iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X"
sudo -- ipvsadm --clear
echo "Reset succeed"
echo "-------------"