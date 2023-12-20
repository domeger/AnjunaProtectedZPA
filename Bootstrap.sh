#!/bin/bash

source /opt/anjuna/azure/env.sh

export RESOURCE_GROUP_NAME="ZPA-Demo"
export LOCATION="westus"
export VNET_NAME="myVnet"
export SUBNET_NAME="mySubnet"
export NSG_NAME="myNSG"
export NIC_NAME="myNic"
export NAME="ZPA"
export PUBLIC_IP_NAME="myPublicIP"
export DOCKER_IMAGE_NAME="zpa"
export DISK_SIZE="20g"

git clone https://github.com/domeger/test2.git /home/admin_overall/test2/

cd /home/admin_overall/test2/

docker build . -t ${DOCKER_IMAGE_NAME}

echo "Logging into Azure with Managed Identity"
az login --identity

echo "Creating a disk from the Docker image BeeKeeperAI"
anjuna-azure-cli disk create --docker-uri=${DOCKER_IMAGE_NAME} --disk-size ${DISK_SIZE}

echo "Getting the Azure subscription details"
az account show && export MY_AZURE_SUBSCRIPTION=$(az account show -o json | jq -r .id)

echo "Creating a new resource group"
az group create --name ${RESOURCE_GROUP_NAME} --location ${LOCATION}

echo "Generating a random suffix for the storage account name"
export RANDOM_SUFFIX=$(cat /dev/urandom | LC_ALL=C tr -dc '[:lower:][:digit:]' | head -c 5)

echo "Setting the storage account name"
export STORAGE_ACCOUNT_NAME="anjunaquickstart${RANDOM_SUFFIX}"

echo "Creating a new storage account"
az storage account create --resource-group ${RESOURCE_GROUP_NAME} --allow-blob-public-access false --name ${STORAGE_ACCOUNT_NAME}

echo "Creating a new storage container"
az storage container create --name mystoragecontainer --account-name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP_NAME}

echo "Creating a Shared Image Gallery"
az sig create --resource-group ${RESOURCE_GROUP_NAME} --gallery-name myGallery1

echo "Creating an image definition in the Shared Image Gallery"
az sig image-definition create --resource-group ${RESOURCE_GROUP_NAME} --gallery-name myGallery1 --gallery-image-definition myFirstDefinition --publisher Anjuna --offer CVMGA --os-type Linux --sku AnjGALinux --os-state specialized --features SecurityType=ConfidentialVMSupported --hyper-v-generation V2 --architecture x64

echo "Uploading disk image to storage account and creating image version in the Shared Image Gallery"
anjuna-azure-cli disk upload --disk disk.vhd --image-name zpa-disk.vhd --storage-account ${STORAGE_ACCOUNT_NAME} --storage-container mystoragecontainer --resource-group ${RESOURCE_GROUP_NAME} --image-gallery myGallery1 --image-definition myFirstDefinition --image-version 0.1.0 --location ${LOCATION} --subscription-id ${MY_AZURE_SUBSCRIPTION}

echo "Creating a VNet, Subnet and Network Security Group"
az network vnet create --resource-group ${RESOURCE_GROUP_NAME} --location ${LOCATION} --name ${VNET_NAME} --address-prefix 10.0.0.0/16
az network vnet subnet create --resource-group ${RESOURCE_GROUP_NAME} --vnet-name ${VNET_NAME} --name ${SUBNET_NAME} --address-prefixes 10.0.0.0/24
az network nsg create --resource-group ${RESOURCE_GROUP_NAME} --name ${NSG_NAME}

echo "Creating a Network Security Group rule and attaching the NSG to the Subnet"
az network nsg rule create --resource-group ${RESOURCE_GROUP_NAME} --nsg-name ${NSG_NAME} --name Allow-5000 --protocol Tcp --direction Inbound --priority 1000 --source-address-prefix '*' --source-port-range '*' --destination-address-prefix '*' --destination-port-range 5000 --access Allow
az network vnet subnet update --resource-group ${RESOURCE_GROUP_NAME} --vnet-name ${VNET_NAME} --name ${SUBNET_NAME} --network-security-group ${NSG_NAME}

echo "Creating a Public IP and a Network Interface Card"
az network public-ip create --resource-group ${RESOURCE_GROUP_NAME} --name ${PUBLIC_IP_NAME} --sku Basic
az network nic create --resource-group ${RESOURCE_GROUP_NAME} --name ${NIC_NAME} --vnet-name ${VNET_NAME} --subnet ${SUBNET_NAME} --network-security-group ${NSG_NAME} --public-ip-address ${PUBLIC_IP_NAME}

echo "Creating an instance of the image"
export INSTANCE_NAME=anjuna-azure-beekeeper-instance && anjuna-azure-cli instance create --name ${INSTANCE_NAME} --location ${LOCATION} --image-gallery myGallery1 --image-definition myFirstDefinition --image-version 0.1.0 --resource-group myResourceGroup --storage-account ${STORAGE_ACCOUNT_NAME} --nics myNic

echo "Describing the created instance"
anjuna-azure-cli instance describe --name ${INSTANCE_NAME} --resource-group ${RESOURCE_GROUP_NAME}

echo "Getting the public IP address of the instance"
export IP_ADDRESS=$(anjuna-azure-cli instance describe --resource-group ${RESOURCE_GROUP_NAME} --name ${INSTANCE_NAME} --json --query publicIps | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | awk 'NR==1') > finished.txt
