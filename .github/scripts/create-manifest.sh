#!/bin/bash

cc_id=$1
cc_name=$2
cc_ver=$3
cc_port=$4
cr_prefix=$5

echo -e "apiVersion: v1
kind: Service
metadata:
  name: $cc_name-$cc_ver
spec:
  type: LoadBalancer
  selector:
    app: $cc_name-$cc_ver
  ports:
    - port: $cc_port
      targetPort: $cc_port
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $cc_name-$cc_ver
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $cc_name-$cc_ver
  template:
    metadata:
      labels:
        app: $cc_name-$cc_ver
    spec:
      hostname: $cc_name-$cc_ver-pod
      containers:
        - name: $cc_name-$cc_ver
          image: $cr_prefix/$cc_name:$cc_ver
          ports:
            - containerPort: $cc_port
          env:
            - name: CC_ID
              value: \"$cc_id\"
            - name: CC_SERVER_ADDRESS
              value: \"$cc_name-$cc_ver-pod:$cc_port\"" > "../k8s/cc-$cc_name-$cc_ver.yaml"
