# Manual deployment of Hyperledger Fabric components on Kubernetes

This document provides the process of deploying individual Fabric components manually
on a Kubernetes cluster.

## TLS Certificate Authority (CA)

### Create a directory for the CA server

Choose a folder structure for your deployment. We will use the following example in
our deployment which will be continued throughout this document.

<div align="center">
    <img src="imgs/tls-ca-struct.png">
</div>

### Create the manifest

Since our primarily focus is to deploy the CA in Kubernetes, we will create the manifest 
using _LoadBalancer_ service type in case it needs to be exposed externally. An [example](../k8s/tls-ca.yaml) is 
provided in the k8s directory of this repository.

You may replace _<org-name>, <port>, <ca-external-ip>, <admin-user>, <admin-pw>_ and _<host-dir>_
with values as required in your use-case. If the above folder is used, replace _<host-dir>_ with
`/root/hfb/tls-ca/server`.

### Bootstrap of CA server

We can now apply this manifest file using the following command in order to start the TLS CA server.

`kubectl apply -f <tls-ca-manifest-file>.yaml`

### Download the *fabric-ca* client binary

Choose a stable version of Hyperledger Fabric and download the corresponding package
from [here](https://github.com/hyperledger/fabric-ca/releases) based on the Operating
System and CPU architecture. We will consider a Linux 64-bit architecture in our example.

`wget https://github.com/hyperledger/fabric-ca/releases/download/v1.5.10/hyperledger-fabric-ca-linux-amd64-1.5.10.tar.gz`

### Set up the CA client

Usually, the client binary will be used in a separate instance (for example, in peer and orderer nodes)
but for the sake of convenience we will set up it in the same instance as the TLA CA server. 
Hence, we can extend the above folder structure to include the client.

`mkdir -p /root/hfb/ca-client`\
`cd /root/hfb/ca-client`\
`tar -xzvf hyperledger-fabric-ca-linux-amd64-1.5.10.tar.gz`

### Save the root certificate

Since this CA server will be used to enable TLS communication in our Fabric network, we need to store
the generated root certificate for the reference of CA client binary for subsequent TLS handshakes.
Hence, we will save it in the client directory.

`mkdir -p /root/hfb/ca-client/tls-root-cert`\
`cd /root/hfb/`
`cp tls-ca/server/crypto/ca-cert.pem ca-client/tls-root-cert/ca-cert.pem`

If multiple instances are used for the Fabric network, you may need to set up the client and store
root certificate in each instance as described above.

### CA client configuration

At minimum, the following 2 environment variables need to be set for the client binary.

`export FABRIC_CA_CLIENT_TLS_CERTFILES=/root/hfb/ca-client/tls-root-cert/ca-cert.pem`\
`export FABRIC_CA_CLIENT_HOME=/root/hfb/ca-client`

You may add these commands to `.bashrc` file for persistence.

### Setup Fabric identity for TLS CA

Each Fabric component needs to be associated with an identity, including the TLS CA server. This 
identity is already registered when the CA server was bootstrapped with our K8s manifest file. 
Use the same credentials now to enroll this identity with the CA client binary. Since this enrollment
will generate a set of files needed for the operations of Fabric, we need to create a directory for the
user in advance.

For an example, if we registered the admin user with a username _'admin'_ and a password _'adminpw'_
on the TLS CA server which is listening on _tls-fabric-test:9090_, we can use the following commands
to enroll the same user with CA client.

`mkdir -p /root/hfb/tls-ca/admin/msp`\
`./fabric-ca-client enroll -d -u https://admin:adminpw@tls-fabric-test:9090 --mspdir /root/hfb/tls-ca/admin/msp`

The resulting folder structure should now appear as follows:
<div align="center">
    <img src="imgs/tls-ca-final-struct.png">
</div>
