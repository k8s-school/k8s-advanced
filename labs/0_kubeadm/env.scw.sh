# Environment for the two-node cluster provisioned on Scaleway by
# `make cluster nb=<N>` in k8s-school/k8s-server/provisioning.
#
# The VMs of participant <I> are named student<I>-1 (master) and student<I>-2
# (worker), after the account they log in with on the training server. So the
# cluster is derived from the login name and there is nothing to edit here:
# student3 gets student3-1 / student3-2, and the ssh config that
# `make cluster-dispatch` wrote into ~/.ssh/config resolves both names.
#
# STUDENT is overridable for anyone whose login is not the account name — the
# trainer, typically: STUDENT=student1 ./create.sh

# DISTRIB="centos"
DISTRIB="ubuntu"

# Read before USER is overwritten below: USER is the login on THIS machine when
# the cluster name is derived, and the ssh login on the NODES afterwards.
STUDENT="${STUDENT:-$USER}"

MASTER="${STUDENT}-1"
NODES="${STUDENT}-2"

# Default account of Scaleway's Ubuntu images, with passwordless sudo.
USER=ubuntu

SCP="scp"
SSH="ssh"
