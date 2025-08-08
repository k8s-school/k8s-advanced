set -euxo pipefail

INSTANCE_TYPE="DEV1-L"
DISTRIBUTION="ubuntu_noble"

for i in $(seq 1 2); do
  INSTANCE_NAME="k8s-$i"
  echo "Creating instance $INSTANCE_NAME..."

  scw instance server create zone="fr-par-1" image=$DISTRIBUTION type="$INSTANCE_TYPE" name=$INSTANCE_NAME
done
