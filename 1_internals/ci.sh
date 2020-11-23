#!/bin/bash

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)

$DIR/ex1.sh
$DIR/ex2-backup.sh
