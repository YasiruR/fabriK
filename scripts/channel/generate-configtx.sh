#!/bin/bash

org_name=$1
ord_cluster_port=$3
ord_external_ip=$4
admin_msp=$7
config_dir=$8

# create arrays
IFS=', ' read -r -a ord_cluster_ips <<< "$2"
IFS=', ' read -r -a ord_external_ports <<< "$5"
IFS=', ' read -r -a ord_certs <<< "$6"

# create OrdererEndpoints
i=0
ord_endpoints=''
consenters=''
for ip in "${ord_cluster_ips[@]}"
do
  if [ $i == 0 ]; then
    ord_endpoints+="- $ip:$ord_cluster_port"

    consenters+="- Host: $ip
        Port: $ord_cluster_port
        ClientTLSCert: ${ord_certs[i]}
        ServerTLSCert: ${ord_certs[i]}"
  else
    ord_endpoints+=$"
      - $ip:$ord_cluster_port"

    consenters+=$"
      - Host: $ip
        Port: $ord_cluster_port
        ClientTLSCert: ${ord_certs[i]}
        ServerTLSCert: ${ord_certs[i]}"
  fi
  i=$((i+1))
done

# create Consenters
#i=0
#consenters=''
#for p in "${ord_external_ports[@]}"
#do
#  if [ $i == 0 ]; then
#    consenters+="- Host: $ord_external_ip
#        Port: $p
#        ClientTLSCert: ${ord_certs[i]}
#        ServerTLSCert: ${ord_certs[i]}"
#  else
#    consenters+=$"
#      - Host: $ord_external_ip
#        Port: $p
#        ClientTLSCert: ${ord_certs[i]}
#        ServerTLSCert: ${ord_certs[i]}"
#  fi
#  i=$((i+1))
#done

echo -e "---
Organizations:
  - &Org1
    Name: $org_name
    ID: $org_name-msp
    MSPDir: $admin_msp
    Policies: &Org1Policies
      Readers:
        Type: Signature
        Rule: \"OR('$org_name-msp.admin', '$org_name-msp.peer', '$org_name-msp.client')\"
      Writers:
        Type: Signature
        Rule: \"OR('$org_name-msp.member')\"
      Admins:
        Type: Signature
        Rule: \"OR('$org_name-msp.admin')\"
      Endorsement:
        Type: Signature
        Rule: \"OR('$org_name-msp.peer')\"
    OrdererEndpoints:
      $ord_endpoints
Capabilities:
  Channel: &ChannelCapabilities
    V2_0: true
  Orderer: &OrdererCapabilities
    V2_0: true
  Application: &ApplicationCapabilities
    V2_5: true
Application: &ApplicationDefaults
  ACLs: &ACLsDefault
    _lifecycle/CheckCommitReadiness: /Channel/Application/Writers
    _lifecycle/CommitChaincodeDefinition: /Channel/Application/Writers
    _lifecycle/QueryChaincodeDefinition: /Channel/Application/Writers
    _lifecycle/QueryChaincodeDefinitions: /Channel/Application/Writers
    lscc/ChaincodeExists: /Channel/Application/Readers
    lscc/GetDeploymentSpec: /Channel/Application/Readers
    lscc/GetChaincodeData: /Channel/Application/Readers
    lscc/GetInstantiatedChaincodes: /Channel/Application/Readers
    qscc/GetChainInfo: /Channel/Application/Readers
    qscc/GetBlockByNumber: /Channel/Application/Readers
    qscc/GetBlockByHash: /Channel/Application/Readers
    qscc/GetTransactionByID: /Channel/Application/Readers
    qscc/GetBlockByTxID: /Channel/Application/Readers
    cscc/GetConfigBlock: /Channel/Application/Readers
    cscc/GetChannelConfig: /Channel/Application/Readers
    peer/Propose: /Channel/Application/Writers
    peer/ChaincodeToChaincode: /Channel/Application/Writers
    event/Block: /Channel/Application/Readers
    event/FilteredBlock: /Channel/Application/Readers
  Organizations:
  Policies: &ApplicationDefaultPolicies
    LifecycleEndorsement:
      Type: ImplicitMeta
      Rule: \"MAJORITY Endorsement\"
    Endorsement:
      Type: ImplicitMeta
      Rule: \"MAJORITY Endorsement\"
    Readers:
      Type: ImplicitMeta
      Rule: \"ANY Readers\"
    Writers:
      Type: ImplicitMeta
      Rule: \"ANY Writers\"
    Admins:
      Type: ImplicitMeta
      Rule: \"MAJORITY Admins\"
  Capabilities:
    <<: *ApplicationCapabilities
Orderer: &OrdererDefaults
  OrdererType: etcdraft
  Addresses:
  BatchTimeout: 2s
  BatchSize:
    MaxMessageCount: 500
    AbsoluteMaxBytes: 10 MB
    PreferredMaxBytes: 2 MB
  MaxChannels: 0
  EtcdRaft:
    Consenters:
      $consenters
    Options:
      TickInterval: 500ms
      ElectionTick: 10
      HeartbeatTick: 1
      MaxInflightBlocks: 5
      SnapshotIntervalSize: 16 MB
  Organizations:
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: \"ANY Readers\"
    Writers:
      Type: ImplicitMeta
      Rule: \"ANY Writers\"
    Admins:
      Type: ImplicitMeta
      Rule: \"MAJORITY Admins\"
    BlockValidation:
      Type: ImplicitMeta
      Rule: \"ANY Writers\"
  Capabilities:
    <<: *OrdererCapabilities
Channel: &ChannelDefaults
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: \"ANY Readers\"
    Writers:
      Type: ImplicitMeta
      Rule: \"ANY Writers\"
    Admins:
      Type: ImplicitMeta
      Rule: \"MAJORITY Admins\"
  Capabilities:
    <<: *ChannelCapabilities
Profiles:
  AppChanEtcdRaft:
    <<: *ChannelDefaults
    Orderer:
      <<: *OrdererDefaults
      OrdererType: etcdraft
      Organizations:
        - <<: *Org1
          Policies:
            <<: *Org1Policies
            Admins:
              Type: Signature
              Rule: \"OR('$org_name-msp.admin')\"
    Application:
      <<: *ApplicationDefaults
      Organizations:
        - <<: *Org1
          Policies:
            <<: *Org1Policies
            Admins:
              Type: Signature
              Rule: \"OR('$org_name-msp.admin')\"
" > "$config_dir/configtx.yaml"

echo "---> generated $config_dir/configtx.yaml"