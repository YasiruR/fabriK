#!/bin/bash

cc_id=$1
cc_name=$2
cc_ver=$3
k8s_ver=$4
cc_port=$5
img_path=$6

fn="cc-$cc_name-$k8s_ver.yaml"

#touch "../k8s/$fn"
#cp ../k8s/cc.yaml "../k8s/$fn"
#
#sed -i "s+'<cc-name>'+$cc_name+g" "../k8s/$fn"
#sed -i "s+'<cc-version>'+$cc_ver+g"  "../k8s/$fn"
#sed -i "s+'<cc-port>'+$cc_port+g"  "../k8s/$fn"
#sed -i "s+'<img-path>'+$img_path+g"  "../k8s/$fn"
#sed -i "s+'<package-id>'+$cc_id+g"  "../k8s/$fn"

echo -e "apiVersion: v1
kind: Service
metadata:
  name: $cc_name-$k8s_ver
spec:
  type: LoadBalancer
  selector:
    app: $cc_name-$k8s_ver
  ports:
    - port: $cc_port
      targetPort: $cc_port
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $cc_name-$k8s_ver
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $cc_name-$k8s_ver
  template:
    metadata:
      labels:
        app: $cc_name-$k8s_ver
    spec:
      hostname: $cc_name-$k8s_ver-pod
      automountServiceAccountToken: false
      containers:
        - name: $cc_name-$k8s_ver
          image: $img_path:$cc_ver
          ports:
            - containerPort: $cc_port
          env:
            - name: CC_ID
              value: \"$cc_id\"
            - name: CC_SERVER_ADDRESS
              value: \"$cc_name-$k8s_ver-pod:$cc_port\"
          resources:
            limits:
              cpu: 500m
              memory: 150Mi
      imagePullSecrets:
              - name: gitlabcred" > "k8s/$fn"