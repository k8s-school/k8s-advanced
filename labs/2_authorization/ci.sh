#!/bin/bash

set -euo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)

FILES=$DIR/*.sh
for f in $FILES
do
  if echo "$f" | grep "ci\.sh"; then
      echo
      ink "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
      ink "NOT processing $f"
      ink "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  else
      echo
      ink "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
      ink "Processing $f"
      ink "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
      sh -c "$f"
  fi
done
