#!/bin/bash

# this is a util script to help with structuring the crypto dependencies to Blockchain Explorer

org='org'
peer='peer2'

rm -r "/root/explorer/$org"
mkdir -p "/root/explorer/$org"
cp -r "/root/hfb/$org/peers" "/root/explorer/$org/"
cp -r "/root/hfb/$org/orderers" "/root/explorer/$org/"

cd "/root/explorer/$org/" || exit
key_file=$(ls peers/$peer/admin/msp/keystore/)
mv "peers/$peer/admin/msp/keystore/$key_file" "org/peers/$peer/admin/msp/keystore/key.pem"
cert_file=$(ls org/peers/$peer/tls/cacerts/)
mv "org/peers/$peer/tls/cacerts/$cert_file" "org/peers/$peer/tls/cacerts/ca-cert.pem"