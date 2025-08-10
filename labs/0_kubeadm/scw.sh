#!/bin/bash
# This script creates two instances on Scaleway and updates the SSH config file to include them.

set -euxo pipefail

INSTANCE_TYPE="DEV1-L"
DISTRIBUTION="ubuntu_noble"

for i in $(seq 1 2); do
  INSTANCE_NAME="k8s-$i"
  echo "Creating instance $INSTANCE_NAME..."

  scw instance server create zone="fr-par-1" image=$DISTRIBUTION type="$INSTANCE_TYPE" ip="$ip_id" name=$INSTANCE_NAME
  instance_id=$(scw instance server list | grep $INSTANCE_NAME | awk '{print $1}')
  ip_address=$(scw instance server wait "$instance_id" | grep PublicIP.Address | awk '{print $2}')

  CONFIG=~/.ssh/config
  HOST_ENTRY="Host $INSTANCE_NAME"
  HOSTNAME_LINE="  HostName $ip_address"
  USER_LINE="  User ubuntu"

  # Update ~/.ssh/config to add the new instance
  if grep -q "^Host $INSTANCE_NAME\$" "$CONFIG"; then
    # Update HostName line for existing Host entry
    awk -v host="$INSTANCE_NAME" -v hostname="$HOSTNAME_LINE" '
      $0 == "Host "host {print; inhost=1; next}
      inhost && $1 == "HostName" {$0=hostname; inhost=0}
      {print}
    ' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
  else
    # Add new Host entry
    {
      echo "$HOST_ENTRY"
      echo "$HOSTNAME_LINE"
      echo "$USER_LINE"
    } >> "$CONFIG"
  fi

  echo "Updated ~/.ssh/config for $INSTANCE_NAME"
done
