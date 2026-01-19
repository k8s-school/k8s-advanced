#!/bin/bash

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting execution of all CKS scripts from directories 5_ and above..."

$DIR/labs/7_supply_chain/1-trivy.sh
$DIR/labs/7_supply_chain/2-cosign.sh
$DIR/labs/1_internals/apiserver-auditlogs.sh
$DIR/labs/6_security_hardening/kube-bench.sh
$DIR/labs/5_runtime_security/falco.sh
# Create a new k8s cluster
$DIR/labs/6_security_hardening/seccomp.sh

echo "All scripts completed successfully!"
