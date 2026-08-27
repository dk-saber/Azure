#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# ==========================================
# CONFIGURATION & VARIABLES
# ==========================================
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
KEY_NAME="${KEY_NAME:-datacenter-kp}"
KEY_PATH="${HOME}/.ssh/${KEY_NAME}"

# ==========================================
# PROMPT FOR MISSING VALUES
# ==========================================
if [ -z "$RESOURCE_GROUP" ]; then
    read -rp "Enter your Resource Group name: " RESOURCE_GROUP
fi

# ==========================================
# STEP 1: Generate RSA Key Pair Locally
# ==========================================
echo -e "\n[1/2] Generating local RSA 2048-bit SSH key pair at ${KEY_PATH}..."

# Create ~/.ssh directory if it does not exist
mkdir -p "${HOME}/.ssh"

# Generate the SSH key pair without a passphrase (-N "")
ssh-keygen -t rsa -b 2048 -f "$KEY_PATH" -N ""

echo " Key pair created successfully."

# ==========================================
# STEP 2: Upload / Register Public Key in Azure
# ==========================================
echo -e "\n[2/2] Importing public key '${KEY_PATH}.pub' into Azure resource group '$RESOURCE_GROUP'..."

az sshkey create \
    --name "$KEY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --public-key "@${KEY_PATH}.pub"

echo -e "\n Public key imported successfully!"