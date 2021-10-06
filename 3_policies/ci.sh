#!/bin/bash

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)

$DIR/ex1-securitycontext.sh
# $DIR/ex2-psp.sh
# $DIR/ex3-psp.sh
$DIR/ex4-network-full.sh
