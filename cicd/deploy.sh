#!/bin/bash

## usage:
# bash deploy.sh -i asset-cc_0.3:34d689e6d -c asset-cc-0-3:5005 -d yasii -u ubuntu -a 10.63.28.50 -k /home/yasi/Documents/work/ceit/remote/k8s-remote -l master-node1 -s /home/yasi/go/src/github.com/YasiruR/fabriK/chaincode

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

## util functions
create_manifest(){
  cc_id=$1
  cc_addr=$2
  cc_name=$3
  cc_ver=$4
  cc_k8s_ver=$5
  d_usr=$6

  # parse chaincode hostname and port from address
  tmp=(${cc_addr//:/ })
  if [ ${#tmp[@]} == 2 ]; then
    cc_host=${tmp[0]}
    cc_port=${tmp[1]}
  elif [[ $cc_addr == http* ]]; then
    cc_host=$(echo "${tmp[1]}" | sed -e "s/^\/\///" )
    cc_port=${tmp[2]}
  fi

  # create asset manifest
  echo -e "apiVersion: v1
kind: Service
metadata:
  name: $cc_name-$cc_k8s_ver
spec:
  type: LoadBalancer
  selector:
    app: $cc_name-$cc_k8s_ver
  ports:
    - port: $cc_port
      targetPort: $cc_port
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $cc_name-$cc_k8s_ver
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $cc_name-$cc_k8s_ver
  template:
    metadata:
      labels:
        app: $cc_name-$cc_k8s_ver
    spec:
      hostname: $cc_name-$cc_k8s_ver-pod
      containers:
        - name: $cc_name-$cc_k8s_ver
          image: $d_usr/$cc_name:$cc_ver
          ports:
            - containerPort: $cc_port
          env:
            - name: CC_ID
              value: \"$cc_id\"
            - name: CC_SERVER_ADDRESS
              value: \"$cc_host-pod:$cc_port\"" > "cc-$cc_name-$cc_k8s_ver.yaml"
  echo "$cc_port"
}

create_dockerfile(){
  cc_name=$1
  cc_k8s_ver=$2
  cc_port=$3
  src=$4

  echo -e "# syntax=docker/dockerfile:1
FROM golang:1.19-alpine

WORKDIR /go/github.com/YasiruR/fabriK/chaincode

COPY $src/go.mod $src/go.sum ./
COPY $src/start.go ./
RUN go mod download
COPY $src/asset ./asset/

RUN CGO_ENABLED=0 GOOS=linux go build -o $cc_name-$cc_k8s_ver
EXPOSE $cc_port

CMD [\"/go/github.com/YasiruR/fabriK/chaincode/$cc_name-$cc_k8s_ver\"]" > Dockerfile
}

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
# create chaincode manifest file
cc_k8s_ver=$(echo "$cc_ver" | tr . -)
cc_port=$(create_manifest $cc_id $cc_addr $cc_name $cc_ver $cc_k8s_ver $d_usr)

# create and deploy Docker image
create_dockerfile $cc_name $cc_k8s_ver $cc_port $src
sudo docker build -t "$d_usr/$cc_name:$cc_ver" "$src"   # compile and build docker image
sudo docker push "$d_usr/$cc_name:$cc_ver"              # push docker image to registry

scp -i "$key" "cc-$cc_name-$cc_k8s_ver.yaml" "$s_usr@$s_addr:$m_path_node"

# log into VM
ssh -i "$key" "$s_usr@$s_addr" "lxc file push $m_path_node/cc-$cc_name-$cc_k8s_ver.yaml $lxc/$m_path_lxc/; lxc exec $lxc -- kubectl apply -f $m_path_lxc/cc-$cc_name-$cc_k8s_ver.yaml"

# todo: when lxc node is not used
