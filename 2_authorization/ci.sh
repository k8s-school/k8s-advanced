#!/bin/bash

set -euxo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)

FILES=$DIR/*.sh
for f in $FILES
do
  if echo "$f" | grep "ci\.sh"; then
      echo
      echo "-------------------------------------------------------------------"
      echo "NOT processing $f"
      echo "-------------------------------------------------------------------"
  else
      echo
      echo "-------------------------------------------------------------------"
      echo "Processing $f"
      echo "-------------------------------------------------------------------"
      sh -c "$f"
done
