#!/bin/bash

set -euxo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)

$DIR/install.sh
$DIR/ex1-hpa.sh
$DIR/ex2-vpa.sh
