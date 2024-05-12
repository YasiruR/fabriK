#!/bin/bash

log_prefix='--->'
sleep_s='10'
ca_client_version='1.5.9'
ord_port=7051

log() {
	echo "$log_prefix $1"
}

# network configs
host=''
tls_ca_host=''
tls_ca_port=''
org_ca_host=''
org_ca_port=''

# fabric configs
org_name='org'
ord_name='ord0'
ord_pw='ordpw'

# file paths
hfb_path='/root/hfb'
tls_admin_msp="$hfb_path/tls-ca/admin/msp"
org_admin_msp="$hfb_path/$org_name/ca/admin/msp"
rcert_path_global="$hfb_path/tls-ca/root-cert"
rcert_file='tls-ca-cert.pem'

# read args
tls_local=0
org_local=0
help=0
while getopts 'a:c:d:e:f:hl:m:o:p:r:s:t:u:' flag; do
  case "${flag}" in
    a) host="${OPTARG}" ;;
    c) org_ca_host="${OPTARG}" ;;
    d) org_admin_msp="${OPTARG}" ;;
    e) org_ca_port="${OPTARG}" ;;
    f) hfb_path="${OPTARG}" ;;
    h) help=1 ;;
    l) tls_admin_msp="${OPTARG}" ;;
    m) ord_manifest_path="${OPTARG}" ;;
    o) org_name="${OPTARG}" ;;
    p) ord_pw="${OPTARG}" ;;
    r) tls_ca_port="${OPTARG}" ;;
    s) sleep_s="${OPTARG}" ;;
    t) tls_ca_host="${OPTARG}" ;;
    u) ord_name="${OPTARG}" ;;
    *) exit 1 ;;
  esac
done

if [[ $help == 1 ]]; then
    echo "
  Usage:
    bash deploy-orderer.sh [arguments]

  Flags:
    a: hostname of the orderer
    c: hostname of the organization CA [must be provided if org CA does not locally exist]
    d: MSP directory path of organization admin [must be provided if org CA locally exists]
    e: port of the organization CA [must be provided if org CA does not locally exist]
    f: root directory where deployment should be done [optional, default: $hfb_path]
    l: MSP directory path of TLS admin [must be provided if TLS CA locally exists]
    m: file path of the orderer manifest [optional, if not provided script will generate a new file as $hfb_path/manifests/$org_name-$ord_name.yaml]
    o: organization name [optional, default: $org_name]
    p: password of orderer user [optional, default: $ord_pw]
    r: port of TLS CA [must be provided if TLS CA does not locally exist]
    s: sleep buffer in seconds [default: 10]
    t: hostname of TLS CA [must be provided if TLS CA does not locally exist]
    u: username of orderer [optional, default: $ord_name]

  - If TLS CA hostname is not provided, the script assumes that it locally exists. In this case, MSP directory
    of the admin TLS user must be provided. This condition applies to organization CA as well.
    "
    exit 0
fi

if [ "$host" == '' ]; then
  echo "hostname of the orderer should be provided [run with -h flag to see more details on usage]"
  exit 0
fi

if [ "$tls_ca_host" == '' ]; then
  tls_local=1
fi

if [ "$org_ca_host" == '' ]; then
  org_local=1
fi

ord_svc="$org_name-$ord_name"

# download client binary to client directory and extract
if [ ! -f "$hfb_path/ca-client/fabric-ca-client" ];
then
	mkdir -p "$hfb_path/ca-client" &&
	cd "$hfb_path/ca-client" &&
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
if [ ! -d "$hfb_path/ca-client/tls-root-cert" ];
then
  mkdir -p "$hfb_path/ca-client/tls-root-cert"
fi

if [ ! -f "$hfb_path/ca-client/tls-root-cert/$rcert_file" ];
then
  cp "$rcert_path_global/$rcert_file" "$hfb_path/ca-client/tls-root-cert/$rcert_file"
  log "copied TLS root certificate to organization"
else
  log "TLS root certificate already exists in $hfb_path/ca-client/tls-root-cert/$rcert_file"
fi

# set env variables for client
export FABRIC_CA_CLIENT_TLS_CERTFILES="$hfb_path/ca-client/tls-root-cert/$rcert_file"
export FABRIC_CA_CLIENT_HOME="$hfb_path/ca-client"

# create orderer directory
mkdir -p "$hfb_path/$org_name/orderers/$ord_name/msp"
mkdir -p "$hfb_path/$org_name/orderers/$ord_name/tls"

# register orderer identity if TLS CA exists locally
if [ $tls_local == 1 ]; then
  log "registering orderer identity with TLS CA server since it exists locally"
  tls_ca_host=$host
  tls_ca_port="$(kubectl get svc "$org_name-tls-ca" | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
  log "TLS CA server is running on $tls_ca_host:$tls_ca_port"
  "$hfb_path"/ca-client/fabric-ca-client register -d --id.name "$ord_name" --id.secret "$ord_pw" --id.type orderer -u "https://$tls_ca_host:$tls_ca_port" --mspdir "$tls_admin_msp"
fi

log "enrolling with TLS CA server"
"$hfb_path"/ca-client/fabric-ca-client enroll -d -u "https://$ord_name:$ord_pw@$tls_ca_host:$tls_ca_port" --csr.hosts "\"0.0.0.0,$host,$ord_svc,$ord_svc-pod\"" --mspdir "$hfb_path/$org_name/orderers/$ord_name/tls"

# register peer identity if organization CA exists locally
if [ $org_local == 1 ]; then
  log "registering orderer identity with organization CA server since it exists locally"
  org_ca_host=$host
  org_ca_port="$(kubectl get svc "$org_name-ca" | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
  log "Org CA server is running on $org_ca_host:$org_ca_port"
  "$hfb_path"/ca-client/fabric-ca-client register -d --id.name "$ord_name" --id.secret "$ord_pw" --id.type orderer -u "https://$org_ca_host:$org_ca_port" --mspdir "$org_admin_msp"
fi

# add NodeOUs
log "creating NodeOU for the orderer user"
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
    OrganizationalUnitIdentifier: orderer" > "$hfb_path/$org_name/orderers/$ord_name/msp/config.yaml"

# enroll peer identity with TLS and organization CA servers
log "enrolling with org CA server"
"$hfb_path"/ca-client/fabric-ca-client enroll -d -u "https://$ord_name:$ord_pw@$org_ca_host:$org_ca_port" --mspdir "$hfb_path/$org_name/orderers/$ord_name/msp"

# parsing crypto file names
keyfile=$(ls "$hfb_path/$org_name/orderers/$ord_name/tls/keystore/")
certfile=$(echo "$tls_ca_host"-"$tls_ca_port" | tr '.' '-' | awk '{print $1".pem"}')

# create the manifest
if [ "$ord_manifest_path" == '' ]; then
  ord_manifest_path="$hfb_path/manifests/$org_name-$ord_name.yaml"
  echo -e "apiVersion: v1
kind: Service
metadata:
  name: $ord_svc
spec:
  type: LoadBalancer
  selector:
    app: $ord_svc
  ports:
    - name: orderer-port
      port: $ord_port
      targetPort: $ord_port
    - name: admin-port
      port: 8051
      targetPort: 8051
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $ord_svc
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $ord_svc
  template:
    metadata:
      labels:
        app: $ord_svc
    spec:
      hostname: $ord_svc-pod
      containers:
        - name: $ord_svc
          image: hyperledger/fabric-orderer:2.5
          ports:
            - containerPort: $ord_port
          volumeMounts:
            - mountPath: /tmp/hyperledger/$org_name/$ord_name
              name: $ord_svc-volume
          workingDir: /opt/gopath/src/github.com/hyperledger/fabric/$org_name/$ord_name
          env:
            - name: ORDERER_GENERAL_LISTENADDRESS
              value: \"$ord_svc-pod\"
            - name: ORDERER_GENERAL_LISTENPORT
              value: \"$ord_port\"
            - name: ORDERER_GENERAL_TLS_ENABLED
              value: \"true\"
            - name: ORDERER_GENERAL_TLS_PRIVATEKEY
              value: \"/tmp/hyperledger/$org_name/$ord_name/tls/keystore/$keyfile\"
            - name: ORDERER_GENERAL_TLS_CERTIFICATE
              value: \"/tmp/hyperledger/$org_name/$ord_name/tls/signcerts/cert.pem\"
            - name: ORDERER_GENERAL_TLS_ROOTCAS
              value: \"/tmp/hyperledger/$org_name/$ord_name/tls/cacerts/$certfile\"
            - name: ORDERER_GENERAL_BOOTSTRAPMETHOD
              value: \"none\"
            - name: ORDERER_GENERAL_LOCALMSPDIR
              value: \"/tmp/hyperledger/$org_name/$ord_name/msp\"
            - name: ORDERER_GENERAL_LOCALMSPID
              value: \"$org_name-msp\"
            - name: ORDERER_FILELEDGER_LOCATION
              value: \"/tmp/hyperledger/$org_name/$ord_name/ledger\"
            - name: ORDERER_CHANNELPARTICIPATION_ENABLED
              value: \"true\"
            - name: ORDERER_ADMIN_LISTENADDRESS
              value: \"$ord_svc-pod:8051\"
            - name: ORDERER_ADMIN_TLS_ENABLED
              value: \"true\"
            - name: ORDERER_ADMIN_TLS_PRIVATEKEY
              value: \"/tmp/hyperledger/$org_name/$ord_name/tls/keystore/$keyfile\"
            - name: ORDERER_ADMIN_TLS_CERTIFICATE
              value: \"/tmp/hyperledger/$org_name/$ord_name/tls/signcerts/cert.pem\"
            - name: ORDERER_ADMIN_TLS_CLIENTAUTHREQUIRED
              value: \"true\"
            - name: ORDERER_ADMIN_TLS_CLIENTROOTCAS
              value: \"/tmp/hyperledger/$org_name/$ord_name/tls/cacerts/$certfile\"
      volumes:
        - name: $ord_svc-volume
          hostPath:
            path: $hfb_path/$org_name/orderers/$ord_name
            type: Directory" > "$ord_manifest_path"
fi

# deploy peer
log "deploying orderer service"
kubectl apply -f "$ord_manifest_path" && log "orderer manifest is being deployed..." && sleep "$sleep_s" && log "kubernetes service is created for orderer ($ord_name)"
