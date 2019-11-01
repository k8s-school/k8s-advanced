#!/bin/bash

set -e

DIR=$(cd "$(dirname "$0")"; pwd -P)

FILES=$1/*.sh
for f in $FILES
do
  echo
  echo "-------------------------------------------------------------------"
  echo "Processing $f"
  echo "-------------------------------------------------------------------"
  sh -c "$f"
done
