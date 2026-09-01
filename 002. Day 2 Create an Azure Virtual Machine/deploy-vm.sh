#!/usr/bin/env bash
set -e

# Configuration Variables
AZ_USER="YOUR_AZURE_ID"
AZ_PASS="YOUR_AZURE_PASS"
VM_NAME="devops-vm"
LOCATION="southcentralus"
IMAGE="Canonical:ubuntu-24_04-lts:server:latest"
VM_SIZE="Standard_B1s"
STORAGE_SKU="Standard_LRS"
DISK_SIZE_GB="30"

echo "==> [1/4] Logging in to Azure..."
az login -u "$AZ_USER" -p "$AZ_PASS" --output none

echo "==> [2/4] Retrieving Resource Group..."
RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)

if [ -z "$RESOURCE_GROUP" ]; then
  echo "Error: No Resource Group found."
  exit 1
fi

echo "Target Resource Group: $RESOURCE_GROUP"

echo "==> [3/4] Creating Virtual Machine '$VM_NAME'..."
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --location "$LOCATION" \
  --image "$IMAGE" \
  --size "$VM_SIZE" \
  --storage-sku "$STORAGE_SKU" \
  --os-disk-size-gb "$DISK_SIZE_GB" \
  --generate-ssh-keys \
  --nsg-rule SSH \
  --output table

echo "==> [4/4] Fetching Public IP and connecting via SSH..."
PUBLIC_IP=$(az vm show -d -g "$RESOURCE_GROUP" -n "$VM_NAME" --query publicIps -o tsv)

echo "VM Public IP: $PUBLIC_IP"
echo "Connecting via SSH..."
ssh -o StrictHostKeyChecking=accept-new "azureuser@$PUBLIC_IP"