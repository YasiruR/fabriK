#!/bin/bash

log_prefix='--->'
sleep_s='10'

hostname=""
hfb_dir=""
help=1
tls_manifest_path=""
org_name=""
tls_admin_pw=""
tls_ca_svc=""
tls_admin=""
ca_client_version=""

# read args
while getopts 'a:d:hm:o:p:s:t:u:v:' flag; do
  case "${flag}" in
    a) hostname="${OPTARG}" ;;
    d) hfb_dir="${OPTARG}" ;;
    h) help=1 ;;
    m) tls_manifest_path="${OPTARG}" ;;
    o) org_name="${OPTARG}" ;;
    p) tls_admin_pw="${OPTARG}" ;;
    s) sleep_s="${OPTARG}" ;;
    t) tls_ca_svc="${OPTARG}" ;;
    u) tls_admin="${OPTARG}" ;;
    v) ca_client_version="${OPTARG}" ;;
    *) exit 1 ;;
  esac
done

## print help
if [[ $help == 1 && $hostname == "" && $hfb_dir == "" && $tls_manifest_path == "" && $ca_client_version == "" && $tls_admin == "" && $tls_admin_pw == "" && $tls_ca_svc == "" && $org_name == "" ]]; then
  echo "
Usage:
  bash deploy-tls-ca.sh [arguments]

Flags:
  -a: hostname of the TLS CA
  -d: root directory to deploy TLS CA [optional, default: /root/hfb]
  -m: file path of the TLS CA manifest [if not specified, a new manifest will be generated]
  -o: organization name [optional, default: org]
  -p: admin user password [optional, default: adminpw]
  -s: sleep buffer in seconds [default: 10]
  -t: Kubernetes service name of TLS CA [optional, default: tls-ca]
  -u: admin username [optional, default: admin]
  -v: Fabric CA client binary version [optional, default: v1.5.9]
  "
  exit 0
fi

# set up variables
if [ "$hostname" == "" ]; then
  echo "Error: hostname of the TLS CA must be provided to run this script. Please refer to
  the manual for more details [bash deploy-tls-ca.sh -h]"
  exit 0
fi

if [ "$hfb_dir" == "" ]; then
  hfb_dir='/root/hfb'
fi

if [ "$ca_client_version" == "" ]; then
  ca_client_version='1.5.9'
fi

if [ "$tls_admin" == "" ]; then
  tls_admin='admin'
fi

if [ "$tls_admin_pw" == "" ]; then
  tls_admin_pw='adminpw'
fi

if [ "$org_name" == "" ]; then
  org_name='org'
fi

if [ "$tls_ca_svc" == "" ]; then
  tls_ca_svc="$org_name-tls-ca"
fi

tls_ca_path="$hfb_dir/tls-ca"

# create manifest if not provided explicitly
if [ "$tls_manifest_path" == "" ]; then
  mkdir -p "$hfb_dir"/manifests
  tls_manifest_path="$hfb_dir/manifests/$org_name-tls-ca.yaml"
  # shellcheck disable=SC2217
  echo -e "apiVersion: v1
kind: Service
metadata:
  name: $tls_ca_svc
spec:
  type: LoadBalancer
  selector:
    app: $tls_ca_svc
  ports:
    - port: 7051
      targetPort: 7051
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $tls_ca_svc
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $tls_ca_svc
  template:
    metadata:
      labels:
        app: $tls_ca_svc
    spec:
      containers:
        - name: $tls_ca_svc
          image: hyperledger/fabric-ca:1.5
          ports:
            - containerPort: 7051
          volumeMounts:
            - mountPath: /tmp/hyperledger/fabric-ca
              name: $tls_ca_svc-volume
          env:
            - name: FABRIC_CA_SERVER_HOME
              value: \"/tmp/hyperledger/fabric-ca/crypto\"
            - name: FABRIC_CA_SERVER_TLS_ENABLED
              value: \"true\"
            - name: FABRIC_CA_SERVER_CSR_CN
              value: \"tls-ca\"
            - name: FABRIC_CA_SERVER_CSR_HOSTS
              value: \"0.0.0.0,$hostname\"
            - name: FABRIC_CA_SERVER_DEBUG
              value: \"true\"
          command: [\"sh\"]
          args: [\"-c\", \"fabric-ca-server start -d -b $tls_admin:$tls_admin_pw --port 7051\"]
      volumes:
        - name: $tls_ca_svc-volume
          hostPath:
            path: $hfb_dir/tls-ca/server
            type: Directory" > "$tls_manifest_path"
fi

log() {
	echo "$log_prefix $1"
}

# setup TLS server
{
mkdir -p "$tls_ca_path/server"
kubectl apply -f "$tls_manifest_path" && log "TLS CA manifest is being deployed..." && sleep "$sleep_s" && log "kubernetes service (name: $tls_ca_svc) has been created for TLS CA"
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

# todo change directory to bin
# download client binary to client directory and extract
if [ ! -f "$hfb_dir/ca-client/fabric-ca-client" ];
then
	mkdir -p "$hfb_dir/ca-client" &&
	cd "$hfb_dir/ca-client" &&
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

# set env variables for client
export FABRIC_CA_CLIENT_TLS_CERTFILES="$tls_ca_path/root-cert/tls-ca-cert.pem"
export FABRIC_CA_CLIENT_HOME="$hfb_dir/ca-client"

# enroll TLS CA admin
mkdir -p "$tls_ca_path/admin/msp"
tls_ca_port="$(kubectl get svc $tls_ca_svc | awk 'FNR == 2 {print $5}' | sed -e "s/^.*://" -e "s/\/TCP//")"
log "$tls_ca_svc service is running on port $tls_ca_port"
"$hfb_dir"/ca-client/fabric-ca-client enroll -d -u "https://$tls_admin:$tls_admin_pw@$hostname:$tls_ca_port" --mspdir "$tls_ca_path/admin/msp"

# copy tls root cert to client directory
mkdir -p "$hfb_dir"/ca-client/tls-root-cert/
cp "$hfb_dir"/tls-ca/root-cert/tls-ca-cert.pem "$hfb_dir"/ca-client/tls-root-cert/

log "registered and enrolled the admin user for TLS CA (ID: $tls_admin, password: $tls_admin_pw)"
log "TLS CA is deployed successfully"
