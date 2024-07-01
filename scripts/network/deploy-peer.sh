#!/bin/bash

log_prefix='--->'
sleep_s='10'
ca_client_version='1.5.9'
port=7051

# network configs
host=''
tls_ca_host=''
tls_ca_port=''
org_ca_host=''
org_ca_port=''

# fabric configs
org_name='org'
peer_name='peer0'
peer_pw='peerpw'

# file paths
hfb_path='/root/hfb'
tls_admin_msp="$hfb_path/tls-ca/admin/msp"
org_admin_msp="$hfb_path/$org_name/ca/admin/msp"
rcert_file='tls-ca-cert.pem'
buildpack='/root/buildpack'

log() {
	echo "$log_prefix $1"
}

# read args
tls_local=0
org_local=0
help=0
while getopts 'a:b:c:d:e:f:hl:m:o:p:r:s:t:u:' flag; do
  case "${flag}" in
    a) host="${OPTARG}" ;;
    b) buildpack="${OPTARG}" ;;
    c) org_ca_host="${OPTARG}" ;;
    d) org_admin_msp="${OPTARG}" ;;
    e) org_ca_port="${OPTARG}" ;;
    f) hfb_path="${OPTARG}" ;;
    h) help=1 ;;
    l) tls_admin_msp="${OPTARG}" ;;
    m) peer_manifest_path="${OPTARG}" ;;
    o) org_name="${OPTARG}" ;;
    p) peer_pw="${OPTARG}" ;;
    r) tls_ca_port="${OPTARG}" ;;
    s) sleep_s="${OPTARG}" ;;
    t) tls_ca_host="${OPTARG}" ;;
    u) peer_name="${OPTARG}" ;;
    *) exit 1 ;;
  esac
done

if [[ $help == 1 ]]; then
    echo "
  Usage:
    bash deploy-peer.sh [arguments]

  Flags:
    a: hostname of the peer
    b: Directory path to external buildpack
    c: hostname of the organization CA [must be provided if org CA does not locally exist]
    d: MSP directory path of organization admin [must be provided if org CA locally exists]
    e: port of the organization CA [must be provided if does not locally exist]
    f: root directory where deployment should be done [optional, default: $hfb_path]
    l: MSP directory path of TLS admin [must be provided if TLS CA locally exists]
    m: file path of the peer manifest [optional, if not provided script will generate a new file as /root/manifests/$org_name-$peer_name.yaml]
    o: organization name [optional, default: org]
    p: password of peer user [optional, default: $peer_pw]
    r: port of TLS CA [must be provided if TLS CA does not locally exist]
    s: sleep buffer in seconds [default: 10]
    t: hostname of TLS CA [must be provided if TLS CA does not locally exist]
    u: username of peer [optional, default: $peer_name]

  - If TLS CA hostname is not provided, the script assumes that it locally exists. In this case, MSP directory
    of the admin TLS user must be provided. This condition applies to organization CA as well.
    "
    exit 0
fi

if [ "$host" == '' ]; then
  echo "hostname of the peer should be provided [run with -h flag to see more details on usage]"
  exit 0
fi

if [ "$rcert_path_global" == '' ]; then
  rcert_path_global="$hfb_path/tls-ca/root-cert"
fi

if [ "$tls_ca_host" == '' ]; then
  tls_local=1
fi

if [ "$org_ca_host" == '' ]; then
  org_local=1
fi

if [ "$org_name" == '' ]; then
  org_name='org'
fi

peer_svc="$org_name-$peer_name"
ca_client_dir="$hfb_path/clients/ca"

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
else
  log "TLS root certificate already exists in $ca_client_dir/tls-root-cert/$rcert_file"
fi

# set env variables for client
export FABRIC_CA_CLIENT_TLS_CERTFILES="$ca_client_dir/tls-root-cert/$rcert_file"
export FABRIC_CA_CLIENT_HOME="$ca_client_dir"

# create peer directory
mkdir -p "$hfb_path/$org_name/peers/$peer_name/msp"
mkdir -p "$hfb_path/$org_name/peers/$peer_name/tls"
mkdir -p "$hfb_path/$org_name/peers/$peer_name/production"

# register peer identity if TLS CA exists locally
if [ $tls_local == 1 ]; then
  log "registering peer identity with TLS CA server since it exists locally"
  tls_ca_host=$host
  tls_ca_port="$(kubectl get svc "$org_name-tls-ca" | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
  log "TLS CA server is running on $tls_ca_host:$tls_ca_port"
  "$hfb_path"/clients/ca/fabric-ca-client register -d --id.name "$peer_name" --id.secret "$peer_pw" --id.type peer -u "https://$tls_ca_host:$tls_ca_port" --mspdir "$tls_admin_msp"
fi

log "enrolling with TLS CA server"
"$hfb_path"/clients/ca/fabric-ca-client enroll -d -u "https://$peer_name:$peer_pw@$tls_ca_host:$tls_ca_port" --csr.hosts "\"0.0.0.0,$host,$peer_svc,$peer_svc-pod\"" --mspdir "$hfb_path/$org_name/peers/$peer_name/tls"

# register peer identity if organization CA exists locally
if [ $org_local == 1 ]; then
  log "registering peer identity with organization CA server since it exists locally"
  org_ca_host=$host
  org_ca_port="$(kubectl get svc "$org_name-ca" | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
  log "Org CA server is running on $org_ca_host:$org_ca_port"
  "$hfb_path"/clients/ca/fabric-ca-client register -d --id.name "$peer_name" --id.secret "$peer_pw" --id.type peer -u "https://$org_ca_host:$org_ca_port" --mspdir "$org_admin_msp"
fi

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
    OrganizationalUnitIdentifier: orderer" > "$hfb_path/$org_name/peers/$peer_name/msp/config.yaml"

# enroll peer identity with TLS and organization CA servers
log "enrolling with org CA server"
"$hfb_path"/clients/ca/fabric-ca-client enroll -d -u "https://$peer_name:$peer_pw@$org_ca_host:$org_ca_port" --mspdir "$hfb_path/$org_name/peers/$peer_name/msp"

# parsing crypto file names
keyfile=$(ls "$hfb_path/$org_name/peers/$peer_name/tls/keystore/")
certfile=$(echo "$tls_ca_host"-"$tls_ca_port" | tr '.' '-' | awk '{print $1".pem"}')

# create the manifest
if [ "$peer_manifest_path" == '' ]; then
  peer_manifest_path="$hfb_path/manifests/$org_name-$peer_name.yaml"
  log "generating manifest file at $peer_manifest_path since it is not provided explicitly"
  echo -e "apiVersion: v1
kind: Service
metadata:
  name: $peer_svc
spec:
  type: LoadBalancer
  selector:
    app: $peer_svc
  ports:
    - name: peer-port
      port: $port
      targetPort: $port
    - name: operations-port
      port: 8181
      targetPort: 8181
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $peer_svc
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $peer_svc
  template:
    metadata:
      labels:
        app: $peer_svc
    spec:
      hostname: $peer_svc-pod
      containers:
        - name: $peer_svc
          image: hyperledger/fabric-peer:2.5
          ports:
            - containerPort: $port
          volumeMounts:
            - mountPath: /tmp/hyperledger/$org_name/$peer_name
              name: $peer_svc-volume
            - mountPath: /host/var/run
              name: $org_name-docker-volume
            - mountPath: /opt/hyperledger/ccaas_builder
              name: buildpack-volume
            - mountPath: /var/hyperledger/production
              name: $peer_svc-prod-volume
          workingDir: /opt/gopath/src/github.com/hyperledger/fabric/$org_name/$peer_name
          env:
            - name: CORE_PEER_ID
              value: \"$peer_svc\"
            - name: CORE_PEER_ADDRESS
              value: \"$peer_svc-pod:$port\"
            - name: CORE_PEER_LOCALMSPID
              value: \"$org_name-msp\"
            - name: CORE_PEER_MSPCONFIGPATH
              value: \"/tmp/hyperledger/$org_name/$peer_name/msp\"
            - name: CORE_PEER_TLS_ENABLED
              value: \"true\"
            - name: CORE_PEER_TLS_CERT_FILE
              value: \"/tmp/hyperledger/$org_name/$peer_name/tls/signcerts/cert.pem\"
            - name: CORE_PEER_TLS_KEY_FILE
              value: \"/tmp/hyperledger/$org_name/$peer_name/tls/keystore/$keyfile\"
            - name: CORE_PEER_TLS_ROOTCERT_FILE
              value: \"/tmp/hyperledger/$org_name/$peer_name/tls/cacerts/$certfile\"
            - name: CORE_PEER_GOSSIP_USELEADERELECTION
              value: \"true\"
            - name: CORE_PEER_GOSSIP_ORGLEADER
              value: \"false\"
            - name: CORE_PEER_GOSSIP_EXTERNALENDPOINT
              value: \"$peer_svc:$port\"
            - name: CORE_OPERATIONS_LISTENADDRESS
              value: \"$peer_svc-pod:8181\"
            - name: CORE_OPERATIONS_TLS_ENABLED
              value: \"false\"
            - name: CORE_VM_ENDPOINT
              value: \"unix:///host/var/run/docker.sock\"
            - name: CORE_CHAINCODE_MODE
              value: \"dev\"
      volumes:
        - name: $peer_svc-volume
          hostPath:
            path: $hfb_path/$org_name/peers/$peer_name
            type: Directory
        - name: $org_name-docker-volume
          hostPath:
            path: /var/run
            type: Directory
        - name: buildpack-volume
          hostPath:
            path: $buildpack
            type: Directory
        - name: $peer_svc-prod-volume
          hostPath:
            path: $hfb_path/$org_name/peers/$peer_name/production
            type: Directory" > "$peer_manifest_path"
fi

# deploy peer
log "deploying peer service"
kubectl apply -f "$peer_manifest_path" && log "peer manifest is being deployed..." && sleep "$sleep_s" && log "kubernetes service is created for peer ($peer_name)"
