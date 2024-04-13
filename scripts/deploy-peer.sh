#!/bin/bash

# network configs
host='master-node2'

# fabric configs
org_name='org2'
peer_name='peer0'
peer_pw='peer0pw'

# file paths
hfb_path='/root/hfb'
config_path="$hfb_path/peers/$peer_name/msp/config.yaml"
org_root_cert_path='cacerts/org-ca.pem'
tls_admin_msp="$hfb_path/tls-ca/admin/msp"

log() {
	echo "$log_prefix $1"
}

# read args
tls_local=0
org_local=0
while getopts 'tof:v' flag; do
  case "${flag}" in
    t) tls_local=1 ;;
    o) org_local=1 ;;
    *) exit 1 ;;
  esac
done

# create peer directory
mkdir -p "$hfb_path/peers/$peer_name/msp"
mkdir -p "$hfb_path/peers/$peer_name/tls"

# add NodeOUs
printf "NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: \"$org_root_cert_path\"
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: \"$org_root_cert_path\"
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: \"$org_root_cert_path\"
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: \"$org_root_cert_path\"
    OrganizationalUnitIdentifier: orderer
" > "$config_path"

# register peer identity if TLS CA exists locally
if [ $tls_local == 1 ]; then
  log "registering peer identity with TLS CA server since locally exists"
  tls_ca_port="$(kubectl get svc "$org_name-tls-ca" | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
  "$hfb_path"/ca-client/fabric-ca-client register -d --id.name "$peer_name" --id.secret "$peer_pw" --id.type peer -u "https://$host:$tls_ca_port" --mspdir "$tls_admin_msp"
fi

