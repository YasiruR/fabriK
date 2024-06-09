#!/bin/bash

log_prefix='--->'

# fabric configs
org_name='org'
peer_name='peer0'
ord_name='ord0'
peer_admin='peer-admin'
peer_admin_pw='peer-adminpw'
chan_name='chan0'

# network configs
org_ca_host=''
org_ca_port=''

# file paths
hfb_dir='/root/hfb'
rcert_file='tls-ca-cert.pem'

# read arguments
help=0
while getopts 'c:d:e:i:l:n:o:p:r:u:' flag; do
  case "${flag}" in
    c) chan_name="${OPTARG}" ;;
    d) hfb_dir="${OPTARG}" ;;
    e) peer_name="${OPTARG}" ;;
    i) org_ca_host="${OPTARG}" ;;
    l) ord_cluster_port="${OPTARG}" ;;
    n) ord_name="${OPTARG}" ;;
    o) org_name="${OPTARG}" ;;
    p) peer_admin_pw="${OPTARG}" ;;
    r) org_ca_port="${OPTARG}" ;;
    u) peer_admin="${OPTARG}" ;;
    *) exit 1 ;;
  esac
done

log() {
  echo "$log_prefix $1"
}

if [[ $ca_client_dir == '' ]]; then
  ca_client_dir="$hfb_dir/clients/ca"
fi

if [[ $org_ca_host == '' ]]; then
  org_ca_host=$(hostname)
fi

if [[ $org_ca_port == '' ]]; then
  org_ca_port="$(kubectl get svc "$org_name-ca" | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
    log "Org CA server is running on $org_ca_host:$org_ca_port"
fi

ord_cluster_ip="$org_name-$ord_name"
ord_cluster_port='7051'
org_admin_msp="$hfb_dir/$org_name/ca/admin/msp"

# set env variables for client
export FABRIC_CA_CLIENT_TLS_CERTFILES="$ca_client_dir/tls-root-cert/$rcert_file"
export FABRIC_CA_CLIENT_HOME="$ca_client_dir"

mkdir -p "$hfb_dir/$org_name/peers/$peer_name/admin/msp"

# add NodeOUs
log "creating NodeOU for the peer user"
printf "NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/$org_ca_host-$org_ca_port.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/$org_ca_host-$org_ca_port.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/$org_ca_host-$org_ca_port.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/$org_ca_host-$org_ca_port.pem
    OrganizationalUnitIdentifier: orderer" > "$hfb_dir/$org_name/peers/$peer_name/admin/msp/config.yaml"

# register and enroll peer admin if not exists already [can improve the file check into a better solution]
if [ -f "$hfb_dir/$org_name/peers/$peer_name/admin/msp/signcerts/cert.pem" ]; then
  log "peer admin already exists for $peer_admin"
else
  log "registering peer admin with organization CA"
  "$ca_client_dir"/fabric-ca-client register -d --id.name "$peer_admin" --id.secret "$peer_admin_pw" --id.type admin -u "https://$org_ca_host:$org_ca_port" --mspdir "$org_admin_msp"
  log "enrolling peer admin with organization CA"
  "$ca_client_dir"/fabric-ca-client enroll -d -u "https://$peer_admin:$peer_admin_pw@$org_ca_host:$org_ca_port" --mspdir "$hfb_dir/$org_name/peers/$peer_name/admin/msp"
  log "peer admin user created with username: $peer_admin and password: $peer_admin_pw"
fi

# create dir for channel
mkdir -p "$hfb_dir/$org_name/peers/$peer_name/channels/$chan_name"

tls_cert_file_name=$(ls "$hfb_dir"/"$org_name"/peers/"$peer_name"/tls/cacerts)
log "TLS file name: $tls_cert_file_name"

# fetch channel blocks
log "executing into peer container"
pod_id=$(kubectl get po | grep ^"$org_name"-"$peer_name" | awk 'FNR == 1 {print $1}')
kubectl exec -it "$pod_id" -- bash -c "
peer channel fetch 0 \"/tmp/hyperledger/$org_name/$peer_name/channels/$chan_name/channel.block\" -c \"$chan_name\" -o \"$ord_cluster_ip:$ord_cluster_port\" --tls --cafile \"/tmp/hyperledger/$org_name/$peer_name/tls/cacerts/$tls_cert_file_name\";
export CORE_PEER_MSPCONFIGPATH=\"/tmp/hyperledger/$org_name/$peer_name/admin/msp\";
peer channel join -b \"/tmp/hyperledger/$org_name/$peer_name/channels/$chan_name/channel.block\" -o \"$ord_cluster_ip:$ord_cluster_port\" --tls --cafile \"/tmp/hyperledger/$org_name/$peer_name/tls/cacerts/$tls_cert_file_name\";
peer channel list -o \"$ord_cluster_ip:$ord_cluster_port\" --tls --cafile \"/tmp/hyperledger/$org_name/$peer_name/tls/cacerts/$tls_cert_file_name\";
exit"
