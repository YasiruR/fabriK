#!/bin/bash

# Prerequisites:
#   1. If TLS CA is located locally on the same machine, can use -l flag for automatic registration
#   2. If not, should register org admin user with TLS CA manually
#     a. These will be used as the admin credentials defined by variables below
#     b. Move root signed certificate of TLS CA OOB to the root directory of the node deploying org admin
#     c. Update this file path in the corresponding variable below
#     d. Update host and port of TLS CA

log_prefix='--->'
sleep_s=10

ca_client_version='1.5.9'

# network params
tls_ca_host='master-node2'
tls_ca_port='30880'
org_ca_host='master-node2'

# fabric configs
org_name='org2'
org_admin="admin-$org_name"
org_admin_pw='adminpw'
org_ca_svc="$org_name-ca"

# file paths
hfb_path='/root/hfb'
admin_path="$hfb_path/$org_name/ca/admin"
org_ca_manifest_path="/root/manifests/$org_name-ca.yaml"
tls_admin_path="$hfb_path/tls-ca/admin" # used only when local TLS is enabled by flag

# root cert configs
rcert_file='tls-ca-cert.pem'
rcert_path_global="$hfb_path/$org_name/tls-ca"

log() {
	echo "$log_prefix $1"
}

# read args
tls_local=0
while getopts 'lf:v' flag; do
  case "${flag}" in
    l) tls_local=1 ;;
    *) exit 1 ;;
  esac
done

# create directories for admin MSP and TLS certificates
mkdir -p "$admin_path/msp"
mkdir -p "$admin_path/tls"

# install wget if does not exist
if [[ $(dpkg -l | grep wget | wc -l) == 0 ]]; then
	log "installing wget..."
	apt install wget  > /dev/null
fi

# download client binary to client directory and extract
if [ ! -f "$hfb_path/ca-client/fabric-ca-client" ];
then
	mkdir -p "$hfb_path/ca-client" &&
	cd "$hfb_path/ca-client" &&
	wget "https://github.com/hyperledger/fabric-ca/releases/download/v$ca_client_version/hyperledger-fabric-ca-linux-amd64-$ca_client_version.tar.gz" &&
	tar -xzvf "hyperledger-fabric-ca-linux-amd64-$ca_client_version.tar.gz" &&
	mv bin/fabric-ca-client . &&
	rm -r bin/ &&
	rm hyperledger-fabric-ca-linux-amd64-1.5.9.tar.gz &&
	log "Fabric CA client v$ca_client_version binary was installed"
	cd ..
else
	log "Fabric ca-client binary exists and hence skipping the installation..."
fi

# setup TLS root certificate for client binary
log "setting up TLS root certificate"
if [ ! -d "$hfb_path/ca-client/tls-root-cert" ];
then
  mkdir -p "$hfb_path/ca-client/tls-root-cert"
fi

if [ ! -f "$hfb_path/ca-client/tls-root-cert/$rcert_file" ];
then
  cp "$rcert_path_global/$rcert_file" "$hfb_path/ca-client/tls-root-cert/$rcert_file"
  log "copied TLS root certificate to organization"
fi

tree "$hfb_path"

# set env variables for client
export FABRIC_CA_CLIENT_TLS_CERTFILES="$hfb_path/ca-client/tls-root-cert/$rcert_file"
export FABRIC_CA_CLIENT_HOME="$hfb_path/ca-client"

# registering organization admin user with TLS CA if locally exists
if [ $tls_local == 1 ]; then
  log "registering organization admin user with TLS CA server since locally exists"
  tls_ca_host="$org_ca_host"
  tls_ca_port="$(kubectl get svc "$org_name-tls-ca" | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
  "$hfb_path"/ca-client/fabric-ca-client register -d --id.name "$org_admin" --id.secret "$org_admin_pw" --id.type admin -u "https://$tls_ca_host:$tls_ca_port" --mspdir "$tls_admin_path/msp"
fi

# enroll org admin user with TLS CA
log "enrolling organization admin user with TLS CA server"
"$hfb_path"/ca-client/fabric-ca-client enroll -d -u "https://$org_admin:$org_admin_pw@$tls_ca_host:$tls_ca_port" --csr.hosts "'0.0.0.0,$org_ca_host,$org_name-ca,$org_name-ca-pod'" --mspdir "$admin_path/tls"

# setup org CA server and deploy
log "deploying CA server"
mkdir -p "$hfb_path/$org_name/ca/server/tls"
cp -r "$admin_path/tls/signcerts" "$hfb_path/$org_name/ca/server/tls/"
keyfile=$(ls "$admin_path/tls/keystore/")
mkdir -p "$hfb_path/$org_name/ca/server/tls/keystore"
cp "$admin_path/tls/keystore/$keyfile" "$hfb_path/$org_name/ca/server/tls/keystore/key.pem"
kubectl apply -f "$org_ca_manifest_path" && log "organization CA manifest is being deployed..." && sleep $sleep_s && log "kubernetes service (name: $org_ca_svc) has been created for the CA of $org_name"

# enroll org admin user with org CA
log "enrolling organization admin user with organization CA server"
org_ca_port="$(kubectl get svc $org_ca_svc | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
log "$org_ca_svc service is running on port $org_ca_port"
"$hfb_path"/ca-client/fabric-ca-client enroll -d -u "https://$org_admin:$org_admin_pw@$org_ca_host:$org_ca_port" --mspdir "$admin_path/msp"

log "registered and enrolled the admin user for organization CA (ID: $org_admin, password: $org_admin_pw)"
log "organization CA is deployed successfully"
