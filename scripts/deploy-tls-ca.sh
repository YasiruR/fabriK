#!/bin/bash

log_prefix='--->'
sleep_s=7

hostname='master-node1'
hfb_path='/root/hfb'
tls_ca_path="$hfb_path/tls-ca"
tls_manifest_path='/root/manifests/tls-ca.yaml'

ca_client_version='1.5.9'
tls_admin='admin-org1-tls-ca'
tls_admin_pw='adminpw'
tls_ca_svc='org1-tls-ca'

log() {
	echo "$log_prefix $1"
}

# setup TLS server
{
mkdir -p "$tls_ca_path/server"
kubectl apply -f "$tls_manifest_path" && log "TLS CA manifest is being deployed..." && sleep $sleep_s && log "kubernetes service (name: $tls_ca_svc) has been created for TLS CA"
} &&
{
# copy tls root certificate to root-cert directory
mkdir -p "$tls_ca_path/root-cert"
cp "$tls_ca_path/server/crypto/ca-cert.pem" "$tls_ca_path/root-cert/tls-ca-cert.pem"
log "files and directories created for TLS CA"
tree "$tls_ca_path/server"
}

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

# set env variables for client
export FABRIC_CA_CLIENT_TLS_CERTFILES="$tls_ca_path/root-cert/tls-ca-cert.pem"
export FABRIC_CA_CLIENT_HOME="$hfb_path/ca-client"

# enroll TLS CA admin
mkdir -p "$tls_ca_path/admin/msp"
tls_ca_port="$(kubectl get svc $tls_ca_svc | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
log "$tls_ca_svc service is running on port $tls_ca_port"
"$hfb_path"/ca-client/fabric-ca-client enroll -d -u "https://$tls_admin:$tls_admin_pw@$hostname:$tls_ca_port" --mspdir "$tls_ca_path/admin/msp"

# copy tls root cert to client directory
mkdir -p /root/hfb/ca-client/tls-root-cert/
cp /root/hfb/tls-ca/root-cert/tls-ca-cert.pem /root/hfb/ca-client/tls-root-cert/

log "registered and enrolled the admin user for TLS CA (ID: $tls_admin, password: $tls_admin_pw)"
log "TLS CA is deployed successfully"
