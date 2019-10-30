#!/bin/sh

set -e
set -x

DIR=$(cd "$(dirname "$0")"; pwd -P)

# ~/src/k8s-school/homefs/.certs
CERT_DIR="$HOME/.certs"
mkdir -p "$CERT_DIR"

ORG="k8s-school"

# Follow "Use case 1" with ns foo instead of office
# in certificate subject CN is the use name and O the group
openssl genrsa -out "$CERT_DIR/employee.key" 2048
openssl req -new -key "$CERT_DIR/employee.key" -out "$CERT_DIR/employee.csr" \
    -subj "/CN=employee/O=$ORG"

# Get key from dind cluster:
docker cp kind-control-plane:/etc/kubernetes/pki/ca.crt "$CERT_DIR"
docker cp kind-control-plane:/etc/kubernetes/pki/ca.key "$CERT_DIR"
# Or on clus0-0@gcp:
# sudo cp /etc/kubernetes/pki/ca.crt $HOME/.certs/ && sudo chown $USER $HOME/.certs/ca.crt
# sudo cp /etc/kubernetes/pki/ca.key $HOME/.certs/ && sudo chown $USER $HOME/.certs/ca.key

openssl x509 -req -in "$CERT_DIR/employee.csr" -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" -CAcreateserial -out "$CERT_DIR/employee.crt" -days 500