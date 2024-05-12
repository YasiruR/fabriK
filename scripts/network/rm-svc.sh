#!/bin/bash

hfb_dir=$2

# removing kubernetes resources
kubectl delete svc $1 &&
kubectl delete deploy $1 --grace-period=0 --force &&
pod_name="$(kubectl get po | grep "^$1.*" | awk 'FNR == 1 {print $1}')" &&
{
  kubectl delete po $pod_name --grace-period=0 --force &
  echo "shutting down resources gracefully..." &
} &&
echo "Kubernetes service, deployment and pod of $1 were deleted"

org_name="$(echo $1 | cut -d '-' -f 1)"

# TLS CA dir
if [[ $1 == org*-tls-ca ]]; then
  {
  rm -r "$1"/tls-ca
  rm -r "$1"/ca-client/tls-root-cert
  rm -r "$1"/"$org_name"/tls-ca
  } || {
  echo "No resources found for $1"
  }
fi

# Org CA dir
if [[ $1 == org*-ca ]]; then
    {
    rm -r "$1"/"$org_name"/ca
    } || {
    echo "No resources found for $1"
    }
fi

# Peer dir
if [[ $1 == org*-peer* ]]; then
    peer_name="$(echo $1 | cut -d '-' -f 2)"
    {
    rm -r "$1"/"$org_name"/peers/"$peer_name"
    } || {
    echo "No resources found for $1"
    }
fi

# Orderer dir
if [[ $1 == org*-ord* ]]; then
    ord_name="$(echo $1 | cut -d '-' -f 2)"
    {
    rm -r "$1"/"$org_name"/orderers/"$ord_name"
    } || {
    echo "No resources found for $1"
    }
fi
