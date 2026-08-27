#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# ==========================================
# CONFIGURATION & VARIABLES
# ==========================================
# Override default values here or leave them blank to prompt for input at runtime
AZURE_USERNAME="${AZURE_USERNAME:-}"
AZURE_PASSWORD="${AZURE_PASSWORD:-}"
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
KEY_NAME="${KEY_NAME:-datacenter-kp}"

# ==========================================
# PROMPT FOR MISSING CREDENTIALS/VALUES
# ==========================================
if [ -z "$AZURE_USERNAME" ]; then
    read -rp "Enter your Azure username: " AZURE_USERNAME
fi

if [ -z "$AZURE_PASSWORD" ]; then
    read -rsp "Enter your Azure password: " AZURE_PASSWORD
    echo ""
fi

if [ -z "$RESOURCE_GROUP" ]; then
    read -rp "Enter your Resource Group name: " RESOURCE_GROUP
fi

# ==========================================
# STEP 1: Authenticate to Azure
# ==========================================
echo -e "\n[1/3] Logging in to Azure CLI..."
az login -u "$AZURE_USERNAME" -p "$AZURE_PASSWORD" > /dev/null

echo " Successfully authenticated."

# ==========================================
# STEP 2: Create the SSH Key Pair
# ==========================================
echo -e "\n[2/3] Creating SSH key '$KEY_NAME' in '$RESOURCE_GROUP'..."
# Generates an RSA 2048-bit key pair and saves the private key to ~/.ssh/
az sshkey create \
    --name "$KEY_NAME" \
    --resource-group "$RESOURCE_GROUP"

# ==========================================
# STEP 3: Verify Key Provisioning
# ==========================================
echo -e "\n[3/3] Verifying SSH key status..."
az sshkey show \
    --name "$KEY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --output table

echo -e "\n Process completed successfully!"
