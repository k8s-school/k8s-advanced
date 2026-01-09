#!/bin/bash

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)

$DIR/etcdctl-get.sh
$DIR/etcdctl-backup.sh
