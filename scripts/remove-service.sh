#!/bin/bash

# removing kubernetes resources
kubectl delete svc $1 &&
kubectl delete deploy $1 &&
pod_name="$(kubectl get po | grep "^$1.*" | awk 'FNR == 1 {print $1}')" &&
{
  kubectl delete po $pod_name &
  echo "shutting down resources gracefully..." &
} &&
echo "Kubernetes service, deployment and pod of $1 were deleted"

org_name="$(echo $1 | cut -d '-' -f 1)"

# TLS CA dir
if [[ $1 == org*-tls-ca ]]; then
  {
  rm -r /root/hfb/tls-ca
  rm -r /root/hfb/ca-client/tls-root-cert
  rm -r /root/hfb/"$org_name"/tls-ca
  } || {
  echo "No resources found for $1"
  }
fi

# Org CA dir
if [[ $1 == org*-ca ]]; then
    {
    rm -r /root/hfb/"$org_name"/ca
    } || {
    echo "No resources found for $1"
    }
fi
