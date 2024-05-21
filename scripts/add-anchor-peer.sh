#!/bin/bash

log_prefix='--->'
help=0

chan='chan0'
org='org'
peer='peer0'
ord='ord0'

hfb_dir='/root/hfb'
block_path=''
version='0'

while getopts 'c:d:f:hn:o:p:' flag; do
  case "${flag}" in
    c) chan="${OPTARG}" ;;
    d) hfb_dir="${OPTARG}" ;;
    f) block_path="${OPTARG}" ;;
    h) help=1 ;;
    n) org="${OPTARG}" ;;
    o) ord="${OPTARG}" ;;
    p) peer="${OPTARG}" ;;
    *) exit 1 ;;
  esac
done

if [ "$block_path" == '' ]; then
  echo "file path of the config block must be provided"
  exit 0
fi

peer_host="$org-$peer"
peer_port='7051'
ord_host="$org-$ord"
ord_port='7051'
client_dir="$hfb_dir/clients"

log() {
  echo "$log_prefix $1"
}

# setting binary path for configtxlator
export PATH=$PATH:"$client_dir/chan"

# check if configtxlator is installed
if [[ $(command -v configtxlator) == '' ]]; then
  echo "configtxlator must be installed to execute this script"
  exit 0
fi

# check if jq is installed
if [[ $(command -v jq) == '' ]]; then
  log "installing jq..."
  apt-get update
  apt-get install -y jq
fi

mkdir -p "$hfb_dir/$org/peers/$peer/artifacts/$chan"
cd "$hfb_dir/$org/peers/$peer/artifacts/$chan" || exit
cp "$block_path" config_block.pb

log "parsing channel block..."
configtxlator proto_decode --input config_block.pb --type common.Block --output config_block.json
log "trimming channel block with data section..."
jq ".data.data[0].payload.data.config" config_block.json > config.json
log "appending anchor peer for $peer..."
jq ".channel_group.groups.Application.groups.\"$org\".values += {\"AnchorPeers\":{\"mod_policy\": \"Admins\",\"value\":{\"anchor_peers\": [{\"host\": \"$peer_host\",\"port\": \"$peer_port\"}]},\"version\": \"$version\"}}" config.json > modified_anchor_config.json
log "encoding original block into protobuf..."
configtxlator proto_encode --input config.json --type common.Config --output config.pb
log "encoding modified block into protobuf..."
configtxlator proto_encode --input modified_anchor_config.json --type common.Config --output modified_anchor_config.pb
log "parsing the difference between two generated files..."
configtxlator compute_update --channel_id "$chan" --original config.pb --updated modified_anchor_config.pb --output anchor_update.pb
log "decoding protobuf into JSON block..."
configtxlator proto_decode --input anchor_update.pb --type common.ConfigUpdate --output anchor_update.json
log "appending headers and metadata to the block..."

res="{\"payload\": {
    \"header\": {
        \"channel_header\": {
                \"channel_id\": \"$chan\",
                \"type\":2
        }
    },
    \"data\": {
        \"config_update\": $(cat anchor_update.json)}}}"

echo "$res" | jq . > anchor_update_in_envelope.json
log "creating the final envelope of the transaction..."
configtxlator proto_encode --input anchor_update_in_envelope.json --type common.Envelope --output anchor_update_in_envelope.pb
log "transaction constructed with the update"

# log into peer and execute the update
log "executing into peer container"
tls_cert_file_name=$(ls "$hfb_dir"/"$org"/peers/"$peer"/tls/cacerts)
log "TLS file name: $tls_cert_file_name"
pod_id=$(kubectl get po | grep ^"$org"-"$peer" | awk 'FNR == 1 {print $1}')
kubectl exec -it "$pod_id" -- bash -c "
cd /tmp/hyperledger/\"$org\"/\"$peer\"/artifacts/\"$chan\";
export CORE_PEER_MSPCONFIGPATH=/tmp/hyperledger/\"$org\"/\"$peer\"/admin/msp;
peer channel update -f anchor_update_in_envelope.pb -c \"$chan\" -o \"$ord_host\":\"$ord_port\" --ordererTLSHostnameOverride \"$ord_host\" --tls --cafile \"/tmp/hyperledger/$org/$peer/tls/cacerts/$tls_cert_file_name\";
exit"