# DISTRIB="centos"
DISTRIB="ubuntu"


MASTER="clus0-0"
NODES="clus0-1"

USER=fabrice_jammes_gmail_com
# USER=k8sstudent_gmail_com

gcloud config set project "coastal-sunspot-206412"
ZONE="us-central1-a"
gcloud config set compute/zone $ZONE

SCP="gcloud compute scp"
SSH="gcloud compute ssh"
