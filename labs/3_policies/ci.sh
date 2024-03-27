#!/bin/bash

set -euxo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)

$DIR/ex1-securitycontext.sh
$DIR/ex2-podsecurity.sh
export EX4_NETWORK_FULL=true
$DIR/ex4-network.sh
