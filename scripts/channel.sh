#!/bin/bash

hostname=''
hfb_dir='/root/hfb'
org_name='org'
chan_name='chan0'
osn_admin='osnadmin'
ord_arg='ord0'
peer_arg='peer0'
sleep_s='10'
help=0

while getopts 'a:c:d:hi:n:o:p:s:' flag; do
  case "${flag}" in
    a) osn_admin="${OPTARG}" ;;
    c) chan_name="${OPTARG}" ;;
    d) hfb_dir="${OPTARG}" ;;
    h) help=1 ;;
    i) hostname="${OPTARG}" ;;
    n) org_name="${OPTARG}" ;;
    o) ord_arg="${OPTARG}" ;;
    p) peer_arg="${OPTARG}" ;;
    s) sleep_s="${OPTARG}" ;;
    *) exit 1 ;;
  esac
done

if [ "$hostname" == '' ]; then
  hostname=$(hostname)
fi

bash channel/join-ord-multiple.sh -i "$hostname" -c "$chan_name" -u "$osn_admin" -n "$ord_arg" -d "$hfb_dir" -o "$org_name"
sleep "$sleep_s"

# parse orderers
IFS=', ' read -r -a ord_list <<< "$ord_arg"

# parse peers
IFS=', ' read -r -a peer_list <<< "$peer_arg"
for peer in "${peer_list[@]}"
do
  bash channel/join-peer.sh -c "$chan_name" -n "${ord_list[0]}" -e "$peer" -d "$hfb_dir" -o "$org_name"
done

