#!/bin/bash

set -euxo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)

$DIR/ex1.sh
$DIR/ex2-quota.sh
$DIR/ex3-limitrange.sh
