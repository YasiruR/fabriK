#!/bin/bash

# this is a util script to help with structuring the crypto dependencies to Blockchain Explorer

org='org'
peer='peer1'

rm -r "/root/explorer/$org"
mkdir -p "/root/explorer/$org"
cp -r "/root/hfb/$org/peers" "/root/explorer/$org/"
cp -r "/root/hfb/$org/orderers" "/root/explorer/$org/"

cd "/root/explorer/$org/" || exit
key_file=$(ls peers/$peer/admin/msp/keystore/)
mv "peers/$peer/admin/msp/keystore/$key_file" "peers/$peer/admin/msp/keystore/key.pem"
cert_file=$(ls peers/$peer/tls/cacerts/)
mv "peers/$peer/tls/cacerts/$cert_file" "peers/$peer/tls/cacerts/ca-cert.pem"