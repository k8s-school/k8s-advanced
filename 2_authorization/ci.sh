#!/bin/bash

set -euxo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)

FILES=$DIR/*.sh
for f in $FILES
do
      echo
      echo "-------------------------------------------------------------------"
      echo "Processing $f"
      echo "-------------------------------------------------------------------"
      sh -c "$f"
done
