# DISTRIB="centos"
DISTRIB="ubuntu"


MASTER="clus0-0"
NODES="clus0-1 clus0-2"

USER=fabrice_jammes_gmail_com
# USER=k8sstudent_gmail_com

gcloud config set project "coastal-sunspot-206412"
ZONE="asia-east1-c"
gcloud config set compute/zone $ZONE

SCP="gcloud compute scp"
SSH="gcloud compute ssh"
