#!/bin/bash

# Prerequisites:
#   1. If TLS CA is located locally on the same machine, can use -t flag for automatic registration
#   2. If organization CA is located locally on the same machine, can use -o flag for automatic registration
#   3. If not, should register org admin user with relevant CAs manually
#     a. These will be used as the admin credentials defined by variables below
#     b. Move root signed certificate of TLS and/or organization CA OOB to the root directory of the node deploying org admin
#     c. Update this file path in the corresponding variable below
#     d. Update host and port of TLS and/or organization CA

log_prefix='--->'
sleep_s=10

# network configs
host='master-node2'
tls_ca_host='master-node1'
tls_ca_port=7000
org_ca_host='master-node1'
org_ca_port=8000

# fabric configs
org_name='org2'
peer_name='peer0'
peer_pw='peer0pw'

# file paths
hfb_path='/root/hfb'
config_path="$hfb_path/peers/$peer_name/msp/config.yaml"
org_root_cert_path='cacerts/org-ca.pem'
tls_admin_msp="$hfb_path/tls-ca/admin/msp"
org_admin_msp="$hfb_path/$org_name/ca/admin/msp"
peer_manifest_path="/root/manifests/$org_name-$peer_name.yaml"

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
  log "registering peer identity with TLS CA server since it exists locally"
  tls_ca_host=host
  tls_ca_port="$(kubectl get svc "$org_name-tls-ca" | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
  "$hfb_path"/ca-client/fabric-ca-client register -d --id.name "$peer_name" --id.secret "$peer_pw" --id.type peer -u "https://$host:$tls_ca_port" --mspdir "$tls_admin_msp"
fi

# register peer identity if organization CA exists locally
if [ $org_local == 1 ]; then
  log "registering peer identity with organization CA server since it exists locally"
  org_ca_port="$(kubectl get svc "$org_name-ca" | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
  "$hfb_path"/ca-client/fabric-ca-client register -d --id.name "$peer_name" --id.secret "$peer_pw" --id.type peer -u "https://$host:$org_ca_port" --mspdir "$org_admin_msp"
fi

# enroll peer identity with TLS and organization CA servers
"$hfb_path"/ca-client/fabric-ca-client enroll -d -u "https://$peer_name:$peer_pw@$tls_ca_host:$tls_ca_port" --csr.hosts "'0.0.0.0,$host,$org_name-peer0,$org_name-peer0-pod'" --mspdir "$hfb_path/peers/$peer_name/tls"
"$hfb_path"/ca-client/fabric-ca-client enroll -d -u "https://$peer_name:$peer_pw@$org_ca_host:$org_ca_port" --mspdir "$hfb_path/peers/$peer_name/msp"

# deploy peer
log "deploying peer service"
keyfile=$(ls "$hfb_path/peers/$peer_name/tls/keystore/")
mv "$hfb_path/peers/$peer_name/tls/keystore/$keyfile" "$hfb_path/peers/$peer_name/tls/keystore/key.pem"
kubectl apply -f "$peer_manifest_path" && log "peer manifest is being deployed..." && sleep $sleep_s && log "kubernetes service is created for peer ($peer_name)"
