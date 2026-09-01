# Day 002: Azure Cloud Challenge - Provisioning a Linux Virtual Machine

## Task Overview

The **Nautilus DevOps team** is planning to migrate a portion of their infrastructure to the Azure cloud incrementally. As part of this migration, you are tasked with creating an Azure Virtual Machine (VM) tailored for DevOps workloads, adhering strictly to resource constraints and accessibility requirements.

---

## Requirements

| Parameter | Value |
| :--- | :--- |
| **VM Name** | `devops-vm` |
| **Region / Location** | `southcentralus` |
| **Operating System Image** | Ubuntu 24.04 LTS (`Canonical:ubuntu-24_04-lts:server:latest`) |
| **VM Size** | `Standard_B1s` |
| **Resource Group** | Existing resource group (e.g., `kml_rg_main-...`) |
| **Storage Disk** | 30 GB, Standard HDD (`Standard_LRS`) |
| **Network Security Group** | Default NSG with inbound SSH access (Port 22 allowed) |
| **Verification** | Successful SSH connectivity into the VM |

---

## Solutions & Implementation Methods

Below are three distinct approaches to provision the requested Virtual Machine: using **Azure CLI**, **Terraform (IaC)**, and the **Azure Portal (GUI)**.

---

### Method 1: Azure CLI (Fastest & Recommended)

Using the Azure CLI is the most efficient method for rapid provisioning during labs and automated pipelines.

#### Step 1: Login and Retrieve Resource Group
Log in to your Azure environment and retrieve the pre-allocated Resource Group name:

```bash
# Login using lab credentials

AZ_USER="kk_lab_user_main-c13ebec970224102@azurefreekmlprod.onmicrosoft.com"
AZ_PASS="kThS8Bu9"

az login -u "$AZ_USER" -p "$AZ_PASS"

# Get existing Resource Group name
RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
echo "Resource Group: $RESOURCE_GROUP"
```

#### Step 2: Create the Virtual Machine
Run `az vm create` configured with all specified parameters:

```bash
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name devops-vm \
  --location southcentralus \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_B1s \
  --storage-sku Standard_LRS \
  --os-disk-size-gb 30 \
  --generate-ssh-keys \
  --nsg-rule SSH
```

#### Step 3: Verify SSH Access
Extract the assigned public IP and initiate an SSH session:

```bash
PUBLIC_IP=$(az vm show -d -g $RESOURCE_GROUP -n devops-vm --query publicIps -o tsv)
ssh azureuser@$PUBLIC_IP
```

---

### Method 2: Terraform (Infrastructure as Code - IaC)

For declarative management and integration into IaC repositories:

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

# Data source to fetch the existing Resource Group
data "azurerm_resource_group" "rg" {
  name = "kml_rg_main-c13ebec970224102" # Replace with actual RG name
}

# 1. Virtual Network & Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "devops-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = "southcentralus"
  resource_group_name = data.azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "devops-subnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# 2. Public IP
resource "azurerm_public_ip" "pip" {
  name                = "devops-vm-pip"
  location            = "southcentralus"
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# 3. Network Security Group (Allow SSH)
resource "azurerm_network_security_group" "nsg" {
  name                = "devops-vm-nsg"
  location            = "southcentralus"
  resource_group_name = data.azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# 4. Network Interface
resource "azurerm_network_interface" "nic" {
  name                = "devops-vm-nic"
  location            = "southcentralus"
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# 5. Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "devops-vm"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = "southcentralus"
  size                = "Standard_B1s"
  admin_username      = "azureuser"

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}
```

#### Execution:
```bash
terraform init
terraform plan
terraform apply -auto-approve
```

---

### Method 3: Azure Portal (GUI Step-by-Step)

1. **Navigate to VMs:** Log in to [Azure Portal](https://portal.azure.com), search for **Virtual machines**, and click **+ Create > Azure virtual machine**.
2. **Basics Tab:**
   - **Subscription / Resource Group:** Select the pre-existing Resource Group.
   - **Virtual Machine Name:** Enter `devops-vm`.
   - **Region:** Select `(US) South Central US`.
   - **Image:** Choose `Ubuntu Server 24.04 LTS - x64 Gen2`.
   - **Size:** Select `Standard_B1s` (1 vCPU, 1 GiB memory).
   - **Authentication type:** SSH public key.
   - **SSH Public Key Source:** Generate new key pair or use existing key.
3. **Disks Tab:**
   - **OS Disk Size:** Select `30 GiB`.
   - **OS Disk Type:** Select `Standard HDD (LRS)`.
4. **Networking Tab:**
   - Leave defaults for VNet/Subnet.
   - **NIC Network Security Group:** Select `Basic`.
   - **Inbound Ports:** Allow `SSH (22)`.
5. **Review + Create:** Click **Review + Create**, validate settings, and select **Create**.
6. Download the key pair if prompted, wait for deployment completion, find the public IP on the VM overview page, and test SSH access.

---

## Key Takeaways & Best Practices

- **Image URN:** When using CLI/IaC, specifying exact URNs (`Canonical:ubuntu-24_04-lts:server:latest`) guarantees exact version matching.
- **Disk Type Selection:** `Standard_LRS` represents low-cost HDD storage, suitable for non-production lab environments.
- **Network Security:** Always restrict Port 22 access to specific source IPs in production settings, rather than leaving it open to `*`.
