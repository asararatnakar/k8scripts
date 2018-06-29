#!/bin/bash

export KUBECONFIG_FOLDER=${PWD}/kube-configs

function createStorage() {
	if [ "$(kubectl get pvc | grep shared-pvc | awk '{print $2}')" != "Bound" ]; then
		echo "The Persistant Volume does not seem to exist or is not bound"
		echo "Creating Persistant Volume"
		
		# making a pv on kubernetes
		echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/storage.yaml"
		kubectl create -f ${KUBECONFIG_FOLDER}/storage.yaml
		sleep 5
		if [ "kubectl get pvc | grep shared-pvc | awk '{print $3}'" != "shared-pv" ]; then
			echo "Success creating PV"
		else
			echo "Failed to create PV"
		fi
	else
		echo "The Persistant Volume exists, not creating again"
	fi
}


function createBlockchain(){
    # echo "Creating Services for blockchain network"
    # Use the yaml file with couchdb
    # echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/blockchain-couchdb-services.yaml"
    # kubectl create -f ${KUBECONFIG_FOLDER}/blockchain-couchdb-services.yaml

    echo "Creating new Deployment"
    # if [ "${WITH_COUCHDB}" == "true" ]; then
        # Use the yaml file with couchdb
        echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/blockchain-couchdb.yaml"
        kubectl create -f ${KUBECONFIG_FOLDER}/blockchain-couchdb.yaml
    # fi

    echo "Checking if all deployments are ready"
    NUMPENDING=$(kubectl get deployments | grep blockchain | awk '{print $5}' | grep 0 | wc -l | awk '{print $1}')
    while [ "${NUMPENDING}" != "0" ]; do
        echo "Waiting on pending deployments. Deployments pending = ${NUMPENDING}"
        NUMPENDING=$(kubectl get deployments | grep blockchain | awk '{print $5}' | grep 0 | wc -l | awk '{print $1}')
        sleep 1
    done

    UTILSSTATUS=$(kubectl get pods utils | grep utils | awk '{print $3}')
    while [ "${UTILSSTATUS}" != "Completed" ]; do
        echo "Waiting for Utils pod to start completion. Status = ${UTILSSTATUS}"
        if [ "${UTILSSTATUS}" == "Error" ]; then
            echo "There is an error in utils pod. Please run 'kubectl logs utils' or 'kubectl describe pod utils'."
            exit 1
        fi
        UTILSSTATUS=$(kubectl get pods utils | grep utils | awk '{print $3}')
    done

    UTILSCOUNT=$(kubectl get pods utils | grep "0/3" | grep "Completed" | wc -l | awk '{print $1}')
    while [ "${UTILSCOUNT}" != "1" ]; do
        UTILSLEFT=$(kubectl get pods utils | grep utils | awk '{print $2}')
        echo "Waiting for all containers in Utils pod to complete. Left = ${UTILSLEFT}"
        UTILSSTATUS=$(kubectl get pods utils | grep utils | awk '{print $3}')
        if [ "${UTILSSTATUS}" == "Error" ]; then
            echo "There is an error in utils pod. Please run 'kubectl logs utils' or 'kubectl describe pod utils'."
            exit 1
        fi
        sleep 1
        UTILSCOUNT=$(kubectl get pods utils | grep "0/3" | grep "Completed" | wc -l | awk '{print $1}')
    done

    echo "Waiting for 15 seconds for peers and orderer to settle"
    sleep 15
}

function checkContainerStatus(){
    while [ "$(kubectl get pod ${1} | grep ${1} | awk '{print $3}')" != "Completed" ]; do
        echo "Waiting for ${1} container to be Completed"
        sleep 1;
    done

    if [ "$(kubectl get pod ${1} | grep ${1} | awk '{print $3}')" == "Completed" ]; then
        echo "${1} Completed Successfully"
    fi

    if [ "$(kubectl get pod ${1} | grep ${1} | awk '{print $3}')" != "Completed" ]; then
        echo "${1} Failed"
    fi
}

function createChannel(){
    PEER_MSPID="Org1MSP"
    CHANNEL_NAME="channel1" 
    # //TODO: Add checks for deletion of the pods
    ## ex: 
    # kubectl delete -f ${KUBECONFIG_FOLDER}/create_channel.yaml
    # kubectl delete -f ${KUBECONFIG_FOLDER}/join_channel.yaml

    echo "Preparing yaml file for create channel"
    sed -e "s/%CHANNEL_NAME%/${CHANNEL_NAME}/g" -e "s/%PEER_MSPID%/${PEER_MSPID}/g" ${KUBECONFIG_FOLDER}/create_channel.yaml.base > ${KUBECONFIG_FOLDER}/create_channel.yaml

    echo "Creating createchannel pod"
    echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/create_channel.yaml"
    kubectl create -f ${KUBECONFIG_FOLDER}/create_channel.yaml

    checkContainerStatus "createchannel"
}
function joinPeerOnOrg(){
    echo "Preparing yaml for joinchannel pod"
    sed -e "s/%PEER_ADDRESS%/${PEER_ADDRESS}/g" -e "s/%CHANNEL_NAME%/${CHANNEL_NAME}/g" -e "s/%PEER_MSPID%/${PEER_MSPID}/g" -e "s|%MSP_CONFIGPATH%|${MSP_CONFIGPATH}|g" ${KUBECONFIG_FOLDER}/join_channel.yaml.base > ${KUBECONFIG_FOLDER}/join_channel.yaml

    echo "Creating joinchannel pod"
    echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/join_channel.yaml"
    kubectl create -f ${KUBECONFIG_FOLDER}/join_channel.yaml

    checkContainerStatus "joinchannel"
}

function joinChannel(){
    echo ""
    echo "=> Join Channel: Running Join Channel on Org1 Peer1"
    CHANNEL_NAME="channel1" PEER_MSPID="Org1MSP" PEER_ADDRESS="blockchain-org1peer1:30110" MSP_CONFIGPATH="/shared/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp" 
    joinPeerOnOrg
    echo "=> Join Channel: Running Join Channel on Org2 Peer1"
    CHANNEL_NAME="channel1" PEER_MSPID="Org2MSP" PEER_ADDRESS="blockchain-org2peer1:30210" MSP_CONFIGPATH="/shared/crypto-config/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp"
    joinPeerOnOrg
}

function installChaincode(){
    echo ""
    echo "=> InstallChaincode: Running Install Chaincode on Org1 Peer1"
    CHAINCODE_NAME="example02" CHAINCODE_VERSION="v1" MSP_CONFIGPATH="/shared/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"  PEER_MSPID="Org1MSP" PEER_ADDRESS="blockchain-org1peer1:30110"


    echo "Preparing yaml for chaincodeinstall"
    sed -e "s/%PEER_ADDRESS%/${PEER_ADDRESS}/g" -e "s/%PEER_MSPID%/${PEER_MSPID}/g" -e "s|%MSP_CONFIGPATH%|${MSP_CONFIGPATH}|g"  -e "s/%CHAINCODE_NAME%/${CHAINCODE_NAME}/g" -e "s/%CHAINCODE_VERSION%/${CHAINCODE_VERSION}/g" ${KUBECONFIG_FOLDER}/chaincode_install.yaml.base > ${KUBECONFIG_FOLDER}/chaincode_install.yaml

    echo "Creating chaincodeinstall pod"
    echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/chaincode_install.yaml"
    kubectl create -f ${KUBECONFIG_FOLDER}/chaincode_install.yaml

    checkContainerStatus "chaincodeinstall"
}

function instantiateChaincode(){
    echo ""
    echo "=> InstantiateChaincode: Running Instantiate Chaincode on Org1 Peer1"
    CHANNEL_NAME="channel1" CHAINCODE_NAME="example02" CHAINCODE_VERSION="v1" MSP_CONFIGPATH="/shared/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"  PEER_MSPID="Org1MSP" PEER_ADDRESS="blockchain-org1peer1:30110"
    sed -e "s/%CHANNEL_NAME%/${CHANNEL_NAME}/g" -e "s/%PEER_ADDRESS%/${PEER_ADDRESS}/g" -e "s/%PEER_MSPID%/${PEER_MSPID}/g" -e "s|%MSP_CONFIGPATH%|${MSP_CONFIGPATH}|g"  -e "s/%CHAINCODE_NAME%/${CHAINCODE_NAME}/g" -e "s/%CHAINCODE_VERSION%/${CHAINCODE_VERSION}/g" ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml.base > ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml

    # echo "Preparing yaml for chaincodeinstantiate"
    # sed -e "s/%PEER_ADDRESS%/${PEER_ADDRESS}/g" -e "s/%PEER_MSPID%/${PEER_MSPID}/g" -e "s|%MSP_CONFIGPATH%|${MSP_CONFIGPATH}|g"  -e "s/%CHAINCODE_NAME%/${CHAINCODE_NAME}/g" -e "s/%CHAINCODE_VERSION%/${CHAINCODE_VERSION}/g" ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml.base > ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml

    echo "Creating chaincodeinstantiate pod"
    echo "Running: kubectl create -f ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml"
    kubectl create -f ${KUBECONFIG_FOLDER}/chaincode_instantiate.yaml

    checkContainerStatus "chaincodeinstantiate"
}

#### create persistent volume and pvc
createStorage

#### create blockchain pods and services 
createBlockchain

#### create channel
createChannel

#### join channel
joinChannel

#### Install Chaincode
installChaincode

#### Instantiate Chaincode
instantiateChaincode