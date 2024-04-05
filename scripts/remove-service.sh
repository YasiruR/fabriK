#!/bin/bash

{
kubectl delete svc $1 &&
kubectl delete deploy $1 &&
pod_name="$(kubectl get po | grep "^$1.*" | awk 'FNR == 1 {print $1}')" &&
{
	kubectl delete po $pod_name &
	echo "shutting down resources gracefully..." &  
} &&
echo "Kubernetes service, deployment and pod of $1 were deleted"
rm -r /root/hfb
} || {
echo "No resources found for $1"
}
