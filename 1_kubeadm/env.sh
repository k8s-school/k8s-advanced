MASTER="clus0-0"
NODES="clus0-1 clus0-2"

USER=fjammes15_gmail_com
# USER=k8sstudent_gmail_com

ZONE=europe-west1-c
gcloud config set compute/zone $ZONE

SCP="gcloud compute scp"
SSH="gcloud compute ssh"
