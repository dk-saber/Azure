# Day 001: Azure Cloud Challenge - Creating an SSH Key Pair

## Task Overview

The **Nautilus DevOps team** is strategizing the migration of a portion of their infrastructure to the Azure cloud. Recognizing the scale of this undertaking, they have opted to approach the migration in incremental steps rather than as a single massive transition. To achieve this, they have segmented large tasks into smaller, more manageable units.

This granular approach enables the team to execute the migration in gradual phases, ensuring smoother implementation and minimizing disruption to ongoing operations. By breaking down the migration into smaller tasks, the Nautilus DevOps team can systematically progress through each stage, allowing for better control, risk mitigation, and optimization of resources throughout the migration process.

---

## Requirements

- **Resource Name:** `datacenter-kp`
- **Key Type:** `rsa`
- **Target Provider:** Microsoft Azure (`azurerm_ssh_public_key` / Azure Compute SSH Public Keys)

---

## Solutions & Implementation Methods

Here are four distinct methods to complete this task: using the **Azure CLI**, **Local Generation + Azure Import**, **Terraform (Infrastructure as Code)**, and the **Azure Portal (GUI)**.

---

### Method 1: Azure CLI (Recommended for DevOps Automation)

Azure CLI provides a fast and scriptable way to generate and manage SSH key pairs directly within Azure resources.

#### Step 1: Authenticate to Azure
Log in to your Azure account using the provided credentials:

```bash
az login -u <YOUR_AZURE_USERNAME> -p "<YOUR_AZURE_PASSWORD>"
```

> **Note:** If your password contains special characters such as `$`, make sure to escape them (e.g., `\$`) or wrap the password in single quotes in Bash environments.

#### Step 2: Create the SSH Key Pair
By default, the `az sshkey create` command generates an **RSA** key pair (2048-bit) and registers the public key resource in Azure while downloading the private key locally to `~/.ssh/`.

```bash
az sshkey create \
  --name datacenter-kp \
  --resource-group <YOUR_RESOURCE_GROUP>
```

#### Step 3: Verify Creation
Confirm that the SSH key resource has been properly provisioned in your Resource Group:

```bash
az sshkey show \
  --name datacenter-kp \
  --resource-group <YOUR_RESOURCE_GROUP>
```

---

### Method 2: Local SSH Key Generation & Azure Import

If you prefer to generate the SSH key pair locally using OpenSSH tooling before importing the public key into Azure:

#### Step 1: Generate RSA Key Pair locally via `ssh-keygen`

```bash
ssh-keygen -t rsa -b 2048 -f ~/.ssh/datacenter-kp -N ""
```

#### Step 2: Upload / Register the Public Key in Azure

```bash
az sshkey create \
  --name datacenter-kp \
  --resource-group <YOUR_RESOURCE_GROUP> \
  --public-key "@~/.ssh/datacenter-kp.pub"
```

---

### Method 3: Terraform (Infrastructure as Code - IaC)

For declarative environment deployments, use Terraform to manage the SSH Public Key lifecycle.

`main.tf`:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "resource_group_name" {
  type    = string
  default = "kml_rg_main-37e83d78889048e2"
}

variable "location" {
  type    = string
  default = "eastus"
}

# Local RSA key generation
resource "tls_private_key" "rsa_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Upload public key to Azure
resource "azurerm_ssh_public_key" "datacenter_kp" {
  name                = "datacenter-kp"
  resource_group_name = var.resource_group_name
  location            = var.location
  public_key          = tls_private_key.rsa_key.public_key_openssh
}

output "private_key_pem" {
  value     = tls_private_key.rsa_key.private_key_pem
  sensitive = true
}
```

#### Commands to Apply:
```bash
terraform init
terraform plan
terraform apply
```

---

### Method 4: Azure Portal (GUI Walkthrough)

1. Open the [Azure Portal](https://portal.azure.com) and sign in with your credentials.
2. In the top search bar, type **SSH Keys** and select **SSH keys** from the service list.
3. Click **+ Create** (or **+ Add**).
4. Under **Project Details**:
   - Select your Subscription.
   - Select your **Resource group**.
5. Under **Instance Details**:
   - Set **Name** to `datacenter-kp`.
   - Set **Key source** to `Generate new key pair`.
   - Set **Key type** to `RSA`.
6. Click **Review + create**, then click **Create**.
7. Download the private key (`datacenter-kp.pem`) when prompted by the browser and store it securely.

---

## Verification & Key Takeaways

- **RSA Standard:** RSA remains a widely compatible key format across cloud virtual machine deployments.
- **Resource Management:** Azure SSH Key resources allow central management and reuse of public keys across multiple Azure VMs within a subscription.
- **Security Best Practice:** Never commit private keys (`datacenter-kp` or `.pem` files) to your Git repository. Ensure `.gitignore` includes `*.pem`, `id_rsa*`, and `~/.ssh/` artifacts.
