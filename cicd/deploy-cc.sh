#!/bin/bash

## parameters
# docker credentials (optional)
cc_addr=""    # chaincode server hostname and IP
cc_id=""      # chaincode package id (eg: asset_8.1:34d689e6d6e6a38f9fe7d697bce355d2cf08f575273b0cd0af331abe0fabb9db)
src=""        # path to source code
d_usr=""      # docker user
s_addr=""     # remote server address
s_usr=""      # user for server
key=""        # path of key file for SSH login
lxc=""        # name of the lxc node

## print help

## read args
while getopts 'a:c:d:i:k:l:s:u:v' flag; do
  case "${flag}" in
    a) s_addr="${OPTARG}" ;;
    c) cc_addr="${OPTARG}" ;;
    d) d_usr="${OPTARG}" ;;
    i) cc_id="${OPTARG}" ;;
    k) key="${OPTARG}" ;;
    l) lxc="${OPTARG}" ;;
    s) src="${OPTARG}" ;;
    u) s_usr="${OPTARG}" ;;
    *) exit 1 ;;
  esac
done

## validate args
# server hostname and ip validation
if [ "$src" == "" ]; then
  src="."
fi

## constant configuration
m_path="/hfb/manifests" # manifest file path
# manifest file name
tmp=(${cc_id//:/ })     # replaces : char with ' ' and returns the array
tmp=(${tmp//_/ })       # splits name and version of chaincode and returns the array
cc_name=${tmp[0]}
cc_ver=${tmp[1]}

## pipeline
sudo docker build -t "$cc_name:$cc_ver" "$src"    # compile and build docker image
sudo docker push "$usr/$cc_name:$cc_ver"          # push docker image to registry

# log into VM
ssh -i "$key" "$s_usr@$s_addr"

# log into lxc node if enabled
lxc shell "$lxc"

# create a manifest in path
mkdir -p "$m_path"
# echo cc service to yaml

# apply manifest