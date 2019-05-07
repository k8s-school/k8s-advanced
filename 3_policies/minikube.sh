curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-amd64 \
  && chmod +x minikube
sudo mv minikube /usr/local/bin

# Then see https://kubernetes.io/docs/tasks/tools/install-minikube/#cleanup-everything-to-start-fresh
# and chapter13
# --vm-driver=none
