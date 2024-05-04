# Fabrik

This repository includes 2 subprojects named Iac and CCaaS to support [Hyperledger Fabric](https://www.hyperledger.org/projects/fabric) 
networks on [Kubernetes](https://kubernetes.io/) clusters.

The IaC directory contains bash scripts and corresponding Kubernetes manifest files to automate
the deployment of Hyperledger Fabric components in Unix-like environments. This documentation
provides the steps to deploy a minimal working Fabric network using the resources in the repository.

Please refer to the [quickstart](#quickstart) for convenient and faster deployment of a network, which
will be carried out through the automation scripts.

Refer to the [detailed process](docs/deploy.md) for manual deployment of individual Fabric components.

CCaaS supports the development and deployment of Fabric chaincodes as a Kubernetes service including
CICD pipelines for both GitHub Actions and Gitlab CI.

## Architecture

The following stack of components provides an overview of a sample architecture where the network was deployed. As
you can note, our Kubernetes cluster was deployed in a containerized environment and therefore the automation scripts
provided in this repository involve resolving through this LXC layer as a part of their processes. If your Kubernetes
cluster is hosted directly on the instance, please feel free to modify the scripts by removing this function.

<div align="center">
    <img src="docs/imgs/stack.png">
</div>

## Quickstart

### Deploy a TLS Certificate Authority (CA)

Execute *deploy-tls-ca.sh* script which can be found in *scripts* directory as follows.

`bash scripts/deploy-tls-ca.sh -a <hostname>`

- `hostname` should be the exposed IP address or hostname of the TLS CA instance
- Additional parameters can be configured with corresponding flags
    - Run `bash scripts/deploy-tls-ca.sh -h` for more details
    - If these parameters not provided, default values will be used as specified in the script

The following folder structure is created upon successful execution of the script. Read
through the logs to verify if no error has occurred during the deployment.

<div align="center">
    <img src="docs/imgs/tls-ca-final-struct.png">
</div>

Verify if TLS CA has been spawned as a Kubernetes service by executing `kubectl get svc` and
`kubectl get po` commands.

To further verify, refer to the logs of the Kubernetes pod by `kubectl logs <pod-id>`.

### Remove a component

Execute the following command to remove a service including the files it created during bootstrap.

`bash scripts/rm-svc.sh <k8s-service-name>`
