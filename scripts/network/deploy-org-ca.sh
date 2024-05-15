#!/bin/bash

# Prerequisites:
#   1. If TLS CA is located locally on the same machine, can use -l flag for automatic registration
#   2. If not, should register org admin user with TLS CA manually
#     a. These should be provided by flags for username and password when deploying this script
#     b. Move root signed certificate of TLS CA OOB to the root directory of the node deploying org admin
#     c. Update this file path in the corresponding variable below
#     d. Update host and port of TLS CA

log_prefix='--->'
sleep_s='10'
ca_client_version='1.5.9'

log() {
	echo "$log_prefix $1"
}

tls_local=0
help=0
tls_ca_host=''
tls_ca_port=''
org_ca_host=''
org_name=''
org_admin=''
org_admin_pw=''
hfb_path=''
admin_path=''
org_ca_manifest_path=''
tls_admin_path=''
rcert_path_global=''

# read args
tls_local=0
while getopts 'a:d:e:f:hi:lm:o:p:r:s:t:u:' flag; do
  case "${flag}" in
    a) admin_path="${OPTARG}" ;;
    d) tls_admin_path="${OPTARG}" ;;
    e) tls_ca_port="${OPTARG}" ;;
    h) help=1 ;;
    i) org_ca_host="${OPTARG}" ;;
    f) hfb_path="${OPTARG}" ;;
    l) tls_local=1 ;;
    m) org_ca_manifest_path="${OPTARG}" ;;
    o) org_name="${OPTARG}" ;;
    p) org_admin_pw="${OPTARG}" ;;
    r) rcert_path_global="${OPTARG}" ;;
    s) sleep_s="${OPTARG}" ;;
    t) tls_ca_host="${OPTARG}" ;;
    u) org_admin="${OPTARG}" ;;
    *) exit 1 ;;
  esac
done

## print help
if [[ $help == 1 ]]; then
  echo "
Usage:
  bash deploy-org-ca.sh [arguments]

Flags:
  a: file path of admin MSP [optional, default: /root/org/ca/admin]
  d: root directory of TLS admin MSP [required if -l is used]
  e: TLS CA server port [must be provided if -l is not used]
  f: root directory to deploy organization CA [optional, default: /root/hfb]
  i: hostname or IP address of organization CA
  l: bool flag if TLS CA is serving locally in the same instance [optional, default: false]
  m: file path of the organization CA manifest [optional, if not specified a new manifest will be generated]
  o: organization name [optional, default: org]
  p: admin user password [optional, default: adminpw]
  r: file path of TLS root certificate [must be provided if -l is not used]
  s: sleep buffer in seconds [default: 10]
  t: TLS CA server hostname or IP address [must be provided if -l is not used]
  u: admin username [optional, default: admin-org]
  "
  exit 0
fi

# set variables
if [ "$admin_path" == "" ]; then
  admin_path="/root/hfb/$org_name/ca/admin"
fi

if [ "$hfb_path" == "" ]; then
  hfb_path='/root/hfb'
fi

if [ "$org_name" == "" ]; then
  org_name='org'
fi

if [ "$org_admin" == "" ]; then
  org_admin='admin-org'
fi

if [ "$org_admin_pw" == "" ]; then
  org_admin_pw='adminpw'
fi

if [ "$rcert_path_global" == "" ]; then
  rcert_path_global="/root/hfb/tls-ca/root-cert"
fi

org_ca_svc="$org_name-ca"
ca_client_dir="$hfb_path/clients/ca"

# if TLS is locally deployed
if [ $tls_local == 0 ]; then
  if [ "$tls_ca_host" == '' ] || [ "$tls_ca_port" == '' ]; then
    echo "if external TLS is used, hostname and port of TLS CA must be provided"
    exit 0
  fi
fi

# root cert configs
rcert_file='tls-ca-cert.pem'

# create manifest if not provided explicitly
if [ "$org_ca_manifest_path" == "" ]; then
  mkdir -p "$hfb_path"/manifests
  org_ca_manifest_path="$hfb_path/manifests/$org_name-ca.yaml"
  echo -e "apiVersion: v1
kind: Service
metadata:
  name: $org_ca_svc
spec:
  type: LoadBalancer
  selector:
    app: $org_ca_svc
  ports:
    - port: 8051
      targetPort: 8051
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $org_ca_svc
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $org_ca_svc
  template:
    metadata:
      labels:
        app: $org_ca_svc
    spec:
      containers:
        - name: $org_ca_svc
          image: hyperledger/fabric-ca:1.5
          ports:
            - containerPort: 8051
          volumeMounts:
            - mountPath: /tmp/hyperledger/fabric-ca
              name: $org_ca_svc-volume
          env:
            - name: FABRIC_CA_SERVER_HOME
              value: \"/tmp/hyperledger/fabric-ca/crypto\"
            - name: FABRIC_CA_SERVER_TLS_ENABLED
              value: \"true\"
            - name: FABRIC_CA_SERVER_CSR_CN
              value: \"$org_ca_svc\"
            - name: FABRIC_CA_SERVER_DEBUG
              value: \"true\"
            - name: FABRIC_CA_SERVER_TLS_CERTFILE
              value: \"/tmp/hyperledger/fabric-ca/tls/signcerts/cert.pem\"
            - name: FABRIC_CA_SERVER_TLS_KEYFILE
              value: \"/tmp/hyperledger/fabric-ca/tls/keystore/key.pem\"
          command: [\"sh\"]
          args: [\"-c\", \"fabric-ca-server start -d -b $org_admin:$org_admin_pw --port 8051\"]
      volumes:
        - name: $org_ca_svc-volume
          hostPath:
            path: $hfb_path/$org_name/ca/server
            type: Directory" > "$org_ca_manifest_path"
fi

# create directories for admin MSP and TLS certificates
mkdir -p "$admin_path/msp"
mkdir -p "$admin_path/tls"

# install wget if does not exist
if [[ $(dpkg -l | grep wget | wc -l) == 0 ]]; then
	log "installing wget..."
	apt install wget  > /dev/null
fi

# download client binary to client directory and extract
if [ ! -f "$ca_client_dir/fabric-ca-client" ];
then
	mkdir -p "$ca_client_dir" &&
	cd "$ca_client_dir" &&
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

# setup TLS root certificate for client binary
log "setting up TLS root certificate"
if [ ! -d "$ca_client_dir/tls-root-cert" ];
then
  mkdir -p "$ca_client_dir/tls-root-cert"
fi

if [ ! -f "$ca_client_dir/tls-root-cert/$rcert_file" ];
then
  cp "$rcert_path_global/$rcert_file" "$ca_client_dir/tls-root-cert/$rcert_file"
  log "copied TLS root certificate to organization"
fi

tree "$hfb_path"

# set env variables for client
export FABRIC_CA_CLIENT_TLS_CERTFILES="$ca_client_dir/tls-root-cert/$rcert_file"
export FABRIC_CA_CLIENT_HOME="$ca_client_dir"

# registering organization admin user with TLS CA if locally exists
if [ $tls_local == 1 ]; then
  log "registering organization admin user with TLS CA server since locally exists"
  tls_ca_host="$org_ca_host"
  tls_ca_port="$(kubectl get svc "$org_name-tls-ca" | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
  log "TLS server found to be running on $tls_ca_host:$tls_ca_port"
  "$hfb_path"/clients/ca/fabric-ca-client register -d --id.name "$org_admin" --id.secret "$org_admin_pw" --id.type admin -u "https://$tls_ca_host:$tls_ca_port" --mspdir "$tls_admin_path"
fi

# enroll org admin user with TLS CA
log "enrolling organization admin user with TLS CA server"
"$hfb_path"/clients/ca/fabric-ca-client enroll -d -u "https://$org_admin:$org_admin_pw@$tls_ca_host:$tls_ca_port" --csr.hosts "\"0.0.0.0,$org_ca_host,$org_ca_svc,$org_ca_svc-pod\"" --mspdir "$admin_path/tls"

# setup org CA server and deploy
log "deploying CA server"
mkdir -p "$hfb_path/$org_name/ca/server/tls"
cp -r "$admin_path/tls/signcerts" "$hfb_path/$org_name/ca/server/tls/"
keyfile=$(ls "$admin_path/tls/keystore/")
mkdir -p "$hfb_path/$org_name/ca/server/tls/keystore"
cp "$admin_path/tls/keystore/$keyfile" "$hfb_path/$org_name/ca/server/tls/keystore/key.pem"
kubectl apply -f "$org_ca_manifest_path" && log "organization CA manifest is being deployed..." && sleep "$sleep_s" && log "kubernetes service (name: $org_ca_svc) has been created for the CA of $org_name"

# enroll org admin user with org CA
log "enrolling organization admin user with organization CA server"
org_ca_port="$(kubectl get svc $org_ca_svc | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
log "$org_ca_svc service is running on port $org_ca_port"
"$hfb_path"/clients/ca/fabric-ca-client enroll -d -u "https://$org_admin:$org_admin_pw@$org_ca_host:$org_ca_port" --mspdir "$admin_path/msp"

# create NodeOU
log "creating NodeOU for the admin user"
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
    OrganizationalUnitIdentifier: orderer
" > "$admin_path/msp/config.yaml"

log "registered and enrolled the admin user for organization CA (ID: $org_admin, password: $org_admin_pw)"
log "organization CA is deployed successfully"
