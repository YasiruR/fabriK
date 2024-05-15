# Manual deployment of Hyperledger Fabric components on Kubernetes

This document provides the process of deploying individual Fabric components manually
on a Kubernetes cluster.

## TLS Certificate Authority (CA)

### 1. Create a directory for the CA server

Choose a folder structure for your deployment. We will use the following example in
our deployment which will be continued throughout this document.

<div align="center">
    <img src="imgs/tls-ca-struct.png" height="15%" width="15%">
</div>

### 2. Create the manifest

Since our primarily focus is to deploy the CA in Kubernetes, we will create the manifest
using _LoadBalancer_ service type in case it needs to be exposed externally. An [example](../k8s/tls-ca.yaml) is
provided in the k8s directory of this repository.

You may replace *\<org-name>*, *\<port>*, *\<ca-external-ip>*, *\<admin-user>*, *\<admin-pw>* and *\<host-dir>*
with values as required in your use-case. If the above folder is used, replace _\<host-dir>_ with
`/root/hfb/tls-ca/server`.

### 3. Bootstrap CA server

We can now apply this manifest file using the following command in order to start the TLS CA server.

`kubectl apply -f <tls-ca-manifest-file>.yaml`

### 4. Download the *fabric-ca* client binary

Choose a stable version of Hyperledger Fabric and download the corresponding package
from [here](https://github.com/hyperledger/fabric-ca/releases) based on the Operating
System and CPU architecture. We will consider a Linux 64-bit architecture in our example.

`wget https://github.com/hyperledger/fabric-ca/releases/download/v1.5.10/hyperledger-fabric-ca-linux-amd64-1.5.10.tar.gz`

### 5. Set up the CA client

Usually, the client binary will be used in a separate instance (for example, in peer and orderer nodes)
but for the sake of convenience we will set up it in the same instance as the TLA CA server.
Hence, we can extend the above folder structure to include the client.

`mkdir -p /root/hfb/ca-client`\
`cd /root/hfb/ca-client`\
`tar -xzvf hyperledger-fabric-ca-linux-amd64-1.5.10.tar.gz`

### 6. Save the root certificate

Since this CA server will be used to enable TLS communication in our Fabric network, we need to store
the generated root certificate for the reference of CA client binary for subsequent TLS handshakes.
Hence, we will save it in the client directory.

`mkdir -p /root/hfb/ca-client/tls-root-cert`\
`cd /root/hfb/`\
`cp tls-ca/server/crypto/ca-cert.pem ca-client/tls-root-cert/ca-cert.pem`

If multiple instances are used for the Fabric network, you may need to set up the client and store
root certificate in each instance as described above.

### 7. CA client configuration

At minimum, the following 2 environment variables need to be set for the client binary.

`export FABRIC_CA_CLIENT_TLS_CERTFILES=/root/hfb/ca-client/tls-root-cert/ca-cert.pem`\
`export FABRIC_CA_CLIENT_HOME=/root/hfb/ca-client`

You may add these commands to `.bashrc` file for persistence.

### 8. Setup Fabric identity for TLS CA

Each Fabric component needs to be associated with an identity, including the TLS CA server. This
identity is already registered when the CA server was bootstrapped with our K8s manifest file.
Use the same credentials now to enroll this identity with the CA client binary. Since this enrollment
will generate a set of files needed for the operations of Fabric, we need to create a directory for the
user in advance.

For an example, if we registered the admin user with a username _'admin'_ and a password _'adminpw'_
on the TLS CA server which is listening on _fabric-tls-ca:9090_, we can use the following commands
to enroll the same user with CA client.

`mkdir -p /root/hfb/tls-ca/admin/msp`\
`./fabric-ca-client enroll -d -u https://admin:adminpw@fabric-tls-ca:9090 --mspdir /root/hfb/tls-ca/admin/msp`

The resulting folder structure should now appear as follows:
<div align="center">
    <img src="imgs/tls-ca-final-struct.png" height="35%" width="35%">
</div>

## Organization Certificate Authority

As similar to the TLS CA, a separate CA server (as recommended) is used within an organization
to generate the identities which will be required to operate the Fabric network.

### 1. Register organization admin with TLS CA server

In order to enable TLS communication by the organization CA, we need to register it as a user with the TLS
CA server. For example, if the user _admin-org1_ with the password _adminpw_ needs to be registered for
the organization _org1_ in the above TLS server, the commands should be executed as follows.

`cd /root/hfb/ca-client`\
`./fabric-ca-client register -d --id.name admin-org1 --id.secret adminpw --id.type admin -u https://fabric-tls-ca:9090 --mspdir /root/hfb/tls-ca/admin/msp`

### 2. Enroll admin user with TLS CA

In order to generate TLS certificates (which will be used for communication by organization CA),
we need to enroll the admin user with a TLS CA server. First we will create the directories required
to bootstrap our admin user followed by the enroll command.

`mkdir -p /root/hfb/org1/ca/admin/msp`\
`mkdir -p /root/hfb/org1/ca/admin/tls`\
`./fabric-ca-client enroll -d -u https://admin-org1:adminpw@fabric-tls-ca:9090 --csr.hosts 'fabric-org1-ca' --mspdir /root/hfb/org1/ca/admin/tls`

### 3. Setup organization CA server

Create the directory to be used by the CA server. In our example, we will use the same instance with
CA client to deploy the CA server.

`mkdir -p /root/hfb/org1/ca/server/tls`

Copy the generated certificates to the server directory.

`cp -r /root/hfb/org1/ca/admin/tls/signcerts /root/hfb/org1/ca/server/tls/`\
`cp -r /root/hfb/org1/ca/admin/tls/keystore /root/hfb/org1/ca/server/tls/keystore/`\
`mv /root/hfb/org1/ca/server/tls/keystore/*.pem /root/hfb/org1/ca/server/tls/keystore/key.pem`

### 4. Bootstrap organization CA server

We can now modify the [sample manifest](../k8s/org-ca.yaml) file provided in the _k8s_ directory as same as
with TLS CA and apply it using _kubectl_. However, in this case, you need to provide the same admin credentials
which were used to enroll with TLS CA server in the bootstrap command of the manifest file.

`kubectl apply -f <org-ca-manifest-file>.yaml`

We can verify the successful launch of CA server by inspecting logs with `kubectl logs <org-ca-pod-id>`

### 5. Generate admin identity with organization CA

Once the server is up and running, we can enroll the admin identity with the organization CA server
which will generate a MSP directory as similar to the one generated in TLS CA.

`./fabric-ca-client enroll -d -u https://admin-org1:adminpw@fabric-org1-ca:9090 --mspdir /root/hfb/org1/ca/admin/msp`

### 6. Configure identity with NodeOU

In recent versions of Fabric, roles are incorporated into identities using NodeOU configurations.
Hence, we need to include a config.yaml file in the MSP directory of the admin user (as well as in
every user that we will come across later in this document).

Then we will generate the configuration file with the following command, assuming that organization
CA server is listening on 9191 and the certificate was generated accordingly.
```
printf "NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: \"cacerts/fabric-org1-ca-9191.pem\"
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: \"cacerts/fabric-org1-ca-9191.pem\"
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: \"cacerts/fabric-org1-ca-9191.pem\"
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: \"cacerts/fabric-org1-ca-9191.pem\"
    OrganizationalUnitIdentifier: orderer
" > /root/hfb/org1/ca/admin/msp
```

In case you have a different file name for the organization CA certificate, you may
replace the certificate file path in the above configuration as required.

## Orderer/Peer

The same instance (as organization CA) or different instances can be used to deploy
orderers and peers. The deployment process will be the same for both peers and orderers,
except for the user type and specific directory paths.

### 1. Create NodeOUs

As similar to the organization CA, we need to create a config.yaml to include NodeOUs.
The content will be the same but make sure to update the certificate file if it different
from the one used in organization CA.

### 2. Create directory for orderer

Since we will be storing TLS certificates and identity MSP, we need to create the
respective directories in advance.

`mkdir -p /root/hfb/org1/orderers/ord1/msp`
`mkdir -p /root/hfb/org1/orderers/ord1/tls`

### 3. Register with TLS CA

In order to enable TLS communication, the node needs to be first registered with the TLS
server. This command* should be executed in the instance where TLS CA is hosted with the
admin user.

`./fabric-ca-client register -d --id.name ord1-org1 --id.secret ord1pw --id.type orderer -u https://fabric-tls-ca:9090 --mspdir /root/hfb/tls-ca/admin/msp`

### 4. Enroll with TLS CA

The following command* needs to be executed in the instance where peer/node will be deployed
in order to generate and store TLS certificates (we assume that the hostname of the orderer
instance is _fabric-org1-ord1_). The credentials should be the same which you
used to register the node with the TLS server.

`./fabric-ca-client enroll -d -u https://ord1-org1:ord1pw@fabric-tls-ca:9090 --csr.hosts 'fabric-org1-ord1' --mspdir /root/hfb/org1/orderers/ord1/tls`

### 5. Register with organization CA

We now need to create an identity for the user within the organization which can be achieved by
executing the following command* with the organization CA.

`./fabric-ca-client register -d --id.name ord1-org1 --id.secret ord1pw --id.type orderer -u https://fabric-org1-ca:9090 --mspdir /root/hfb/org1/ca/admin/msp`

### 6. Enroll with organization CA

We can now create the MSP related to the orderer with the enroll command* as follows.

`./fabric-ca-client enroll -d -u https://ord1-org1:ord1pw@fabric-org1-ca:9090 --mspdir /root/hfb/org1/orderers/ord1/msp`

### 7. Deploy peer/orderer

As similar with the CAs, we can now modify the corresponding sample manifest file
in [k8s directory](../k8s) as necessary and apply it with _kubectl_ command.

`kubectl apply -f <orderer/peer-manifest-file>.yaml`

Execute `kubectl logs <pod-id>` of the relevant service to inspect logs and verify
if the deployment is successful.

*In case of a peer, replace the type as _peer_ along with the appropriate credentials and
directory paths.
