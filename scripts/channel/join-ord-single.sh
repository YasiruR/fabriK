#!/bin/bash

log_prefix='--->'
bin_version='2.5.7'
ca_client_version='1.5.9'

# fabric config
org_name='org'
chan_name='chan0'
ord_name='ord0'
osn_admin='osnadmin'
osn_admin_pw='adminpw'

# network config
host=''
tls_port=''
ord_cluster_port='7051'
ord_admin_cluster_port='8051'

# file paths
hfb_dir='/root/hfb'

# read arguments
help=0
while getopts 'c:d:i:l:m:n:o:p:r:t:u:' flag; do
  case "${flag}" in
    i) host="${OPTARG}" ;;
    c) chan_name="${OPTARG}" ;;
    d) hfb_dir="${OPTARG}" ;;
    l) ord_cluster_port="${OPTARG}" ;;
    m) ord_admin_cluster_port="${OPTARG}" ;;
    n) ord_name="${OPTARG}" ;;
    o) org_name="${OPTARG}" ;;
    p) osn_admin_pw="${OPTARG}" ;;
    r) tls_port="${OPTARG}" ;;
    t) tls_host="${OPTARG}" ;;
    u) osn_admin="${OPTARG}" ;;
    *) exit 1 ;;
  esac
done

ord_external_ip="$host"
tls_admin_msp="$hfb_dir/tls-ca/admin/msp"
org_admin_msp="$hfb_dir/$org_name/ca/admin/msp"
osn_tls_dir="$hfb_dir/$org_name/$osn_admin/tls"
ord_cert="$hfb_dir/$org_name/orderers/$ord_name/tls/signcerts/cert.pem"

ord_svc="$org_name-$ord_name"   # should be changed in case different
tls_svc="$org_name-tls-ca"      # should be changed in case different

if [ "$tls_host" == '' ]; then
  tls_host="$host"
fi

client_dir="$hfb_dir/clients"

log() {
	echo "$log_prefix $1"
}

# parse tls port if local
if [ "$tls_port" == '' ]; then
  tls_port="$(kubectl get svc $tls_svc | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
fi

# parse orderer information
tmp_list="$(kubectl get svc "$ord_svc" | awk 'FNR == 2 {print $5}')"
tmp_ports=(${tmp_list//,/ })
for p in "${tmp_ports[@]}"; do
  if [[ "$p" == "$ord_cluster_port"* ]]; then
    ord_external_port="$(echo $p | sed -e "s/^.*://" -e "s/\/TCP//")"
  fi
  if [[ "$p" == "$ord_admin_cluster_port"* ]]; then
    ord_admin_external_port="$(echo $p | sed -e "s/^.*://" -e "s/\/TCP//")"
  fi
done

log "orderer is running on $ord_external_ip:$ord_external_port (cluster port: $ord_cluster_port)"
log "TLS CA server is running on $tls_host:$tls_port"

# generate configtx.yaml [conditional execution to handle channel.sh invocation]
mkdir -p "$hfb_dir/config/$chan_name"
if [ -f ./generate-configtx.sh ]; then
  bash generate-configtx.sh "$org_name" "$ord_svc" "$ord_cluster_port" "$ord_external_ip" "$ord_external_port" "$ord_cert" "$org_admin_msp" "$hfb_dir/config"
else
  bash ./channel/generate-configtx.sh "$org_name" "$ord_svc" "$ord_cluster_port" "$ord_external_ip" "$ord_external_port" "$ord_cert" "$org_admin_msp" "$hfb_dir/config"
fi

# download configtxgen tool
if [ ! -f "$client_dir/chan/configtxgen" ];
then
  mkdir -p "$client_dir/chan" &&
	cd "$client_dir/chan" &&
	wget "https://github.com/hyperledger/fabric/releases/download/v$bin_version/hyperledger-fabric-linux-amd64-$bin_version.tar.gz" &&
	tar -xzvf "hyperledger-fabric-linux-amd64-$bin_version.tar.gz" &&
	mv bin/configtxgen bin/osnadmin . && rm -r bin/ &&
	rm -r config/ &&
	rm -r builders/ &&
	rm "hyperledger-fabric-linux-amd64-$bin_version.tar.gz" &&
	log "Fabric configtxgen v$bin_version binary was installed"
else
	log "Fabric configtxgen binary exists and hence skipping the installation..."
fi

# set env var
export FABRIC_CFG_PATH="$hfb_dir/config"
export PATH=$PATH:"$client_dir/chan"
log "Fabric config env var: $FABRIC_CFG_PATH"
log "Path var: $PATH"

# create genesis block
log "creating genesis block for $chan_name"
configtxgen -profile AppChanEtcdRaft -outputBlock "$hfb_dir/config/$chan_name/genesis_block.pb" -channelID "$chan_name"

# download client binary to client directory and extract
if [ ! -f "$client_dir/ca/fabric-ca-client" ];
then
	mkdir -p "$client_dir/ca" &&
	cd "$client_dir/ca" &&
	wget "https://github.com/hyperledger/fabric-ca/releases/download/v$ca_client_version/hyperledger-fabric-ca-linux-amd64-$ca_client_version.tar.gz" &&
	tar -xzvf "hyperledger-fabric-ca-linux-amd64-$ca_client_version.tar.gz" &&
	mv bin/fabric-ca-client . &&
	rm -r bin/ &&
	rm "hyperledger-fabric-ca-linux-amd64-$ca_client_version.tar.gz" &&
	log "Fabric CA client v$ca_client_version binary was installed"
	cd ..
else
	log "Fabric ca-client binary exists and hence skipping the installation..."
fi

# set env variables for client (todo)
export FABRIC_CA_CLIENT_TLS_CERTFILES="$client_dir/ca/tls-root-cert/tls-ca-cert.pem"
export FABRIC_CA_CLIENT_HOME="$client_dir/ca"

# create TLS root certificate under org admin
mkdir -p "$hfb_dir/$org_name/ca/admin/msp/tlscacerts"
cp "$client_dir/ca/tls-root-cert/tls-ca-cert.pem" "$hfb_dir/$org_name/ca/admin/msp/tlscacerts/"

cd "$client_dir/ca" || exit
# check if OSN admin exists for the given id
res=$(./fabric-ca-client identity list --id "$osn_admin")
if [ $? -eq 0 ]; then
  log "OSN admin already exists for $osn_admin"
else
  # create OSN admin dir
  mkdir -p "$osn_tls_dir"

  # generate TLS certs and MSP for admin
  log "registering OSN admin with TLS server"
  ./fabric-ca-client register -d --id.name "$osn_admin" --id.secret "$osn_admin_pw" --id.type client -u "https://$tls_host:$tls_port" --mspdir "$tls_admin_msp"
  log "enrolling OSN admin user"
  ./fabric-ca-client enroll -d -u "https://$osn_admin:$osn_admin_pw@$tls_host:$tls_port" --csr.hosts "\"0.0.0.0,$host,$ord_svc,$ord_svc-pod\"" --mspdir "$osn_tls_dir"
fi

# set env var (todo change cert file prefix for ips)
keyfile=$(ls "$osn_tls_dir/keystore/")
export OSN_TLS_CA_ROOT_CERT="$osn_tls_dir/cacerts/$tls_host-$tls_port.pem"
export ADMIN_TLS_SIGN_CERT="$osn_tls_dir/signcerts/cert.pem"
export ADMIN_TLS_PRIVATE_KEY="$osn_tls_dir/keystore/$keyfile"
log "environment variables are set for OSN client binary"

# join orderer to channel
log "joining orderer to $chan_name"
osnadmin channel join --channelID "$chan_name" --config-block "$hfb_dir/config/$chan_name/genesis_block.pb" -o "$ord_external_ip:$ord_admin_external_port" --ca-file "$OSN_TLS_CA_ROOT_CERT" --client-cert "$ADMIN_TLS_SIGN_CERT" --client-key "$ADMIN_TLS_PRIVATE_KEY"

# check status
log "checking status of $chan_name"
osnadmin channel list --channelID "$chan_name" -o "$ord_external_ip:$ord_admin_external_port" --ca-file "$OSN_TLS_CA_ROOT_CERT" --client-cert "$ADMIN_TLS_SIGN_CERT" --client-key "$ADMIN_TLS_PRIVATE_KEY"
