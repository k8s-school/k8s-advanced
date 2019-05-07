MASTER="cluster0-0"
NODES="cluster0-1 cluster0-2"

ZONE=europe-west1-c
gcloud config set compute/zone $ZONE

SCP="gcloud compute scp"
SSH="gcloud compute ssh"
