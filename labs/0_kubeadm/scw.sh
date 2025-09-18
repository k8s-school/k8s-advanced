#!/bin/bash
# This script creates two instances on Scaleway and updates the SSH config file to include them.

set -euxo pipefail

INSTANCE_TYPE="DEV1-L"
INSTANCE_TYPE="GP1-S"
DISTRIBUTION="ubuntu_noble"
INSTANCE_COUNT=2
INSTANCE_PREFIX="k8s-"
DELETE_INSTANCE=false

user=ubuntu

usage() {
  echo "Usage: $0 [-d]"
  echo "  -d    Delete existing instances with the prefix '$INSTANCE_PREFIX'"
  echo "  No options will create tw instances with the prefix '$INSTANCE_PREFIX'"
  exit 1
}

# Add option to delete existing instances with optargs
while getopts ":hd" opt; do
  case $opt in
    d)
      DELETE_INSTANCE=true
      ;;
    h)
      usage
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# If DELETE_INSTANCE is set, delete the specified instance
if [ "$DELETE_INSTANCE" = true ]; then
  for instance_id in $(scw instance server list | grep "$INSTANCE_PREFIX" | awk '{print $1}'); do
    echo "Deleting instance $instance_id..."
    ip_address=$(scw instance server wait "$instance_id" | grep PublicIP.Address | awk '{print $2}')
    scw instance server terminate "$instance_id"
    scw instance ip delete "$ip_address"
    echo "Instance $instance_id deleted."
  done
  exit 0
fi

for i in $(seq 1 $INSTANCE_COUNT); do
  INSTANCE_NAME="${INSTANCE_PREFIX}${i}"
  echo "Creating instance $INSTANCE_NAME..."

  scw instance server create zone="fr-par-1" image=$DISTRIBUTION type="$INSTANCE_TYPE"  name=$INSTANCE_NAME
  instance_id=$(scw instance server list | grep $INSTANCE_NAME | awk '{print $1}')
  ip_address=$(scw instance server wait "$instance_id" | grep PublicIP.Address | awk '{print $2}')

  CONFIG=~/.ssh/config
  HOST_ENTRY="Host $INSTANCE_NAME"
  HOSTNAME_LINE="  HostName $ip_address"
  USER_LINE="  User $user"

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

for i in $(seq 1 $INSTANCE_COUNT); do
  INSTANCE_NAME="${INSTANCE_PREFIX}${i}"
  instance_id=$(scw instance server list | grep $INSTANCE_NAME | awk '{print $1}')
  ip_address=$(scw instance server wait "$instance_id" | grep PublicIP.Address | awk '{print $2}')

  # Remove the instance public key from known_hosts
  ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$ip_address"
  until ssh -o "StrictHostKeyChecking no" $user@"$ip_address" true 2> /dev/null
    do
      echo "Waiting for sshd on $ip_address..."
      sleep 5
  done
  echo "Adding $INSTANCE_NAME to known_hosts..."
  ssh-keyscan -v -H "$ip_address" >> ~/.ssh/known_hosts
done

