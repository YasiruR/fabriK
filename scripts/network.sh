#!/bin/bash

hostname=''
hfb_dir='/root/hfb'
org_name='org'
n_peers=1
n_ords=1
sleep_s='20'
help=0
remove=0

while getopts 'd:hi:n:o:p:rs:' flag; do
  case "${flag}" in
    d) hfb_dir="${OPTARG}" ;;
    h) help=1 ;;
    i) hostname="${OPTARG}" ;;
    n) org_name="${OPTARG}" ;;
    o) n_ords="${OPTARG}" ;;
    p) n_peers="${OPTARG}" ;;
    r) remove=1 ;;
    s) sleep_s="${OPTARG}" ;;
    *) exit 1 ;;
  esac
done

if [[ $help == 1 ]]; then
    echo "
  Usage:
    bash network.sh [operation] [arguments]

  Arguments:
    d: root directory for deployment [default: $hfb_dir]
    i: hostname of the peer [required]
    n: name of the organization [default: org]
    o: number of orderers [default: 1]
    p: number of peers [default: 1]
    r: remove the network started with the organization name
    s: sleep buffer in seconds [default: 10]
    "
    exit 0
fi

log() {
  if [ "$1" == '' ]; then
    printf "\n\n"
    exit 0
  fi
  printf "\n### $1\n"
}

if [ $remove == 1 ]; then
  declare -a list=$(kubectl get svc | grep "^$org_name.*" | awk '{print $1}')
  for s in "${list[@]}"
  do
    log "removing $s..."
    bash ./network/rm-svc.sh "$s" "$hfb_dir"
  done
  rm -r "$hfb_dir"
  exit 0
fi

if [ "$hostname" == '' ]; then
  echo "hostname should be provided [run with -h for more information]"
  exit 0
fi

logSuccess() {
  if [ $n_peers == 1 ]; then
    if [ $n_ords == 1 ]; then
      log "network is up and running with a peer and an orderer"
    else
      log "network is up and running with a peer and $n_ords orderers"
    fi
  else
    if [ $n_ords == 1 ]; then
      log "network is up and running with $n_peers peers and an orderer"
    else
      log "network is up and running with $n_peers peers and $n_ords orderers"
    fi
  fi
}

if [ $remove == 0 ]; then
  mkdir -p "$hfb_dir"
  log "initializing TLS CA deployment..."
  bash ./network/deploy-tls-ca.sh -a "$hostname" -d "$hfb_dir" -o "$org_name" -s "$sleep_s"
  log "initializing organization CA deployment..."
  bash ./network/deploy-org-ca.sh -i "$hostname" -l -d "$hfb_dir"/tls-ca/admin/msp -o "$org_name" -s "$sleep_s"

  for (( i=0; i<$n_peers; i++ ))
  do
    log "initializing peer$i deployment..."
    bash ./network/deploy-peer.sh -a "$hostname" -d "$hfb_dir"/"$org_name"/ca/admin/msp -l "$hfb_dir"/tls-ca/admin/msp -u "peer$i" -o "$org_name" -s "$sleep_s"
  done

  for (( i=0; i<$n_ords; i++ ))
  do
    log "initializing ord$i deployment..."
    bash ./network/deploy-orderer.sh -a "$hostname" -d "$hfb_dir"/"$org_name"/ca/admin/msp -l "$hfb_dir"/tls-ca/admin/msp -u "ord$i" -o "$org_name" -s "$sleep_s"
  done
  logSuccess
  exit 0
fi
