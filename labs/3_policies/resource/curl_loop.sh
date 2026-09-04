# Poll a NodePort service from outside the cluster, to watch a network policy
# take effect. Watch the packets on the node with:
#   tcpdump port 30657 -i any
#
# Defaults to your own worker node, student<ID>-2; override with NODE=.
NODE="${NODE:-${USER}-2}"
while true
do
curl "http://$NODE:30657"
done
