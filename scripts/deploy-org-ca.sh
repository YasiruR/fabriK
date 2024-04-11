#!/bin/bash

# Prerequisites:
#   1. Register org admin user with TLS CA manually
#       a. These will be used as the admin credentials defined by variables below
#       b. Update key file and sign certificate in the manifest
#   2. Move root signed certificate of TLS CA OOB to the root directory of the node deploying org admin
#       a. This file path should be updated in the corresponding variable below

log_prefix='--->'
sleep_s=7

ca_client_version='1.5.9'

# network params
tls_ca_host='master-node1'
tls_ca_port='31749'
org_ca_host='master-node1'

# fabric configs
org_name='org1'
org_admin="admin-$org_name"
org_admin_pw='adminpw'
org_ca_svc="$org_name-ca"

# file paths
hfb_path='/root/hfb'
admin_path="$hfb_path/$org_name/ca/admin"
tls_root_cert_path="$hfb_path/$org_name/tls-ca/root-cert"
root_cert_file='tls-ca-cert.pem'
org_ca_manifest_path="/root/manifests/$org_name-ca.yaml"

log() {
	echo "$log_prefix $1"
}

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
if [ ! -d "$tls_root_cert_path" ];
then
  mkdir -p "$tls_root_cert_path"
fi

if [ ! -f "$tls_root_cert_path/$root_cert_file" ];
then
  mv "/root/$root_cert_file" "$tls_root_cert_path/$root_cert_file"
fi

# set env variables for client
export FABRIC_CA_CLIENT_TLS_CERTFILES="$tls_root_cert_path/$root_cert_file"
export FABRIC_CA_CLIENT_HOME="$hfb_path/ca-client"

# enroll org admin user with TLS CA
"$hfb_path"/ca-client/fabric-ca-client enroll -d -u "https://$org_admin:$org_admin_pw@$tls_ca_host:$tls_ca_port" --csr.hosts "'0.0.0.0,$org_ca_host,$org_name-ord0,$org_name-ord1,$org_name-peer0,$org_name-peer1,$org_name-client0,$org_name-client1'" --mspdir "$admin_path/tls"

# setup org CA server and deploy
mkdir -p "$hfb_path/$org_name-ca/server/tls"
cp -r "$admin_path/tls/signcerts" "$hfb_path/$org_name-ca/server/tls/"
cp "$admin_path/tls/keystore/*" "$hfb_path/$org_name-ca/server/tls/keystore/key.pem"
kubectl apply -f "$org_ca_manifest_path" && log "organization CA manifest is being deployed..." && sleep $sleep_s && log "kubernetes service (name: $org_ca_svc) has been created for the CA of $org_name"

# enroll org admin user with org CA
org_ca_port="$(kubectl get svc $org_ca_svc | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
log "$org_ca_svc service is running on port $org_ca_port"
"$hfb_path"/ca-client/fabric-ca-client enroll -d -u "https://$org_admin:$org_admin_pw@$org_ca_host:$org_ca_port" --mspdir "$admin_path/msp"

log "registered and enrolled the admin user for organization CA (ID: $org_admin, password: $org_admin_pw)"
log "organization CA is deployed successfully"
