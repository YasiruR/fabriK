#!/bin/bash

## prerequisites
# user must have logged into a docker account of the relevant registry

## parameters
# docker credentials (optional)
cc_addr=""    # chaincode server hostname and port
cc_id=""      # chaincode package id (eg: asset_8.1:34d689e6d6e6a38f9fe7d697bce355d2cf08f575273b0cd0af331abe0fabb9db)
src=""        # path to source code
d_usr=""      # docker user
s_addr=""     # remote server address
s_usr=""      # user for server
key=""        # path of key file for SSH login
lxc=""        # name of the lxc node
help=0        # for manual

## constant configuration
m_path_node="/home/ubuntu/manifests"  # manifest file path in remote server
m_path_lxc="/root/hfb/manifests"      # manifest file path in lxc container

## read args
while getopts 'a:c:d:hi:k:l:s:u:v' flag; do
  case "${flag}" in
    a) s_addr="${OPTARG}" ;;
    c) cc_addr="${OPTARG}" ;;
    d) d_usr="${OPTARG}" ;;
    h) help=1 ;;
    i) cc_id="${OPTARG}" ;;
    k) key="${OPTARG}" ;;
    l) lxc="${OPTARG}" ;;
    s) src="${OPTARG}" ;;
    u) s_usr="${OPTARG}" ;;
    *) exit 1 ;;
  esac
done

## print help
if [[ $help == 1 && $s_addr == "" && $cc_addr == "" && $d_usr == "" && $cc_id == "" && $key == "" && $lxc == "" && $src == "" && $s_usr == "" ]]; then
  echo "Usage:
  bash deploy.sh [arguments]

Example:
   bash deploy-cc.sh -i sample_chaincode_1.1:34d689e6d6e60af331abe0fabb9db -c https://test:9000 -d testuser

Flags:
  -a: address of a remote server where Kubernetes is running [string]
  -c: address of the chaincode server (cluster-ip:port) [string]
  -d: username of the Docker registry [string]
  -h: help [bool]
  -i: chaincode package ID returned by a Fabric peer [string]
  -k: private key path for SSH login to the remote server [string]
  -l: lxc container name if enabled [string]
  -s: if not the current directory, path to the root directory of go chaincode implementation [string]
  -u: user of the remote server [string]"
  exit 0
fi

## validate args
# server hostname and ip validation
if [ "$src" == "" ]; then
  src="."
fi

# manifest file name
tmp=(${cc_id//:/ })     # replaces : char with ' ' and returns the array
tmp=(${tmp//_/ })       # splits name and version of chaincode and returns the array
cc_name=${tmp[0]}
cc_ver=${tmp[1]}

## pipeline
#sudo docker build -t "$cc_name:$cc_ver" "$src"    # compile and build docker image
#sudo docker push "$usr/$cc_name:$cc_ver"          # push docker image to registry

# create chaincode manifest file
cc_k8s_ver=$(echo "$cc_ver" | tr . -)
bash create-manifest.sh $cc_addr $cc_name $cc_ver $cc_k8s_ver $d_usr
scp -i "$key" "cc-$cc_name-$cc_k8s_ver.yaml" "$s_usr@$s_addr:$m_path_node"

# log into VM
ssh -i "$key" "$s_usr@$s_addr" "lxc file push $m_path_node/cc-$cc_name-$cc_k8s_ver.yaml $lxc/$m_path_lxc/; lxc exec $lxc -- kubectl apply -f $m_path_lxc/cc-$cc_name-$cc_k8s_ver.yaml"
#ssh -i "$key" "$s_usr@$s_addr" "lxc file push $m_path_node/cc-$cc_name-$cc_k8s_ver.yaml $lxc/$m_path_lxc/; lxc shell $lxc; kubectl apply -f $m_path_lxc/cc-$cc_name-$cc_k8s_ver.yaml"

# log into lxc node if enabled
#if [ "$lxc" != "" ]; then
#  lxc shell "$lxc"
#fi

# create a manifest in path
#mkdir -p "$m_path_lxc"

# apply manifest
#kubectl apply -f "$m_path_lxc/cc-$cc_name-$cc_k8s_ver.yaml"