#!/bin/bash

cc_id=$1
cc_addr=$2
cc_name=$3
cc_ver=$4
cc_k8s_ver=$5
d_usr=$6

# parse chaincode hostname and port from address
tmp=(${cc_addr//:/ })
if [ ${#tmp[@]} == 2 ]; then
  cc_host=${tmp[0]}
  cc_port=${tmp[1]}
elif [[ $cc_addr == http* ]]; then
  cc_host=$(echo "${tmp[1]}" | sed -e "s/^\/\///" )
  cc_port=${tmp[2]}
fi

# create asset manifest

echo "$cc_k8s_ver"
echo -e "apiVersion: v1
kind: Service
metadata:
  name: $cc_name-$cc_k8s_ver
spec:
  type: LoadBalancer
  selector:
    app: $cc_name-$cc_k8s_ver
  ports:
    - port: $cc_port
      targetPort: $cc_port
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $cc_name-$cc_k8s_ver
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $cc_name-$cc_k8s_ver
  template:
    metadata:
      labels:
        app: $cc_name-$cc_k8s_ver
    spec:
      hostname: $cc_name-$cc_k8s_ver-pod
      containers:
        - name: $cc_name-$cc_k8s_ver
          image: $d_usr/$cc_name:$cc_ver
          ports:
            - containerPort: $cc_port
          env:
            - name: CC_ID
              value: \"$cc_id\"
            - name: CC_SERVER_ADDRESS
              value: \"$cc_host-pod:$cc_port\"" > "cc-$cc_name-$cc_k8s_ver.yaml"

