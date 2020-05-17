# DISTRIB="centos"
DISTRIB="ubuntu"


MASTER="clus0-0"
NODES="clus0-1 clus0-2"

USER=fabrice_jammes_clermont_in2p3_fr
# USER=k8sstudent_gmail_com

ZONE="asia-east1-c"
gcloud config set compute/zone $ZONE

SCP="gcloud compute scp"
SSH="gcloud compute ssh"
