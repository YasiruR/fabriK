#!/bin/bash

artifacts_dir=''
chan_name=''
new_org=''
new_org_msp=''

while getopts 'c:d:m:o:' flag; do
  case "${flag}" in
    c) chan_name="${OPTARG}" ;;
    d) artifacts_dir="${OPTARG}" ;;
    m) new_org_msp="${OPTARG}" ;;
    o) new_org="${OPTARG}" ;;
    *) exit 1 ;;
  esac
done

new_org_config_json="$new_org.json"

if [ "$artifacts_dir" == '' ] || [ "$chan_name" == '' ] || [ "$new_org_msp" == '' ] || [ "$new_org" == '' ] ; then
  echo "missing required parameter (artifacts directory, channel name, new org name or new org msp id)"
  exit 0
fi

if [ ! -d "$artifacts_dir" ];
then
  mkdir -p "$artifacts_dir"
fi
cd "$artifacts_dir"

configtxlator proto_decode --input config_block.pb --type common.Block --output config_block.json &&
jq ".data.data[0].payload.data.config" config_block.json > config.json &&
jq -s '.[0] * {"channel_group":{"groups":{"Application":{"groups": {"'$new_org_msp'":.[1]}}}}}' config.json "$new_org_config_json" > modified_config.json &&
configtxlator proto_encode --input config.json --type common.Config --output config.pb &&
configtxlator proto_encode --input modified_config.json --type common.Config --output modified_config.pb &&
configtxlator compute_update --channel_id "$chan_name" --original config.pb --updated modified_config.pb --output "$new_org"_update.pb &&
configtxlator proto_decode --input "$new_org"_update.pb --type common.ConfigUpdate --output "$new_org"_update.json &&
echo '{"payload":{"header":{"channel_header":{"channel_id":"'$chan_name'", "type":2}},"data":{"config_update":'$(cat "$new_org"_update.json)'}}}' | jq . > "$new_org"_update_in_envelope.json &&
configtxlator proto_encode --input "$new_org"_update_in_envelope.json --type common.Envelope --output "$new_org"_update_in_envelope.pb