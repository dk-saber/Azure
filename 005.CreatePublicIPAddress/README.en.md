# Azure Public IP Address: GUI, Azure CLI and Terraform

🌐 **Languages:** [Français](README.fr.md) · **English** · [Deutsch](README.de.md)

## Context

A company is migrating part of its infrastructure to Azure. To keep risk low, the migration is split into small, independent steps instead of one big move. The first building block is a **Public IP address**: an address reachable from the Internet that can later be attached to a virtual machine, a load balancer or a gateway.

**Goal:** create a Public IP address named `datacenter-pip` in an existing resource group.

## Key concepts

| Concept | Example | Counter-example |
|---|---|---|
| Public vs private IP | `20.50.10.4` can be reached from the Internet (e.g. SSH) | `10.0.0.4` is only reachable inside the Azure network |
| Static allocation | The address never changes, even if the VM is stopped, so DNS records stay valid | A dynamic address can change after a stop/start and DNS then points nowhere |
| Standard SKU | Secure by default (closed until a Network Security Group allows traffic) | The Basic SKU is retired by Azure (since 30 September 2025), so do not use it |

Why create the IP separately from the VM? It can outlive the VM: if the VM is destroyed and recreated, the address (and any firewall rule that references it) stays the same.

## Prerequisites

- An Azure subscription and an **existing resource group** (note its name and region).
- For the Terraform method: Terraform >= 1.5 installed on your machine. The Azure CLI is **not** required.
- For the Terraform method: a **Service Principal** (client ID + client secret) with the *Contributor* role on the resource group, plus your tenant ID and subscription ID.

## Method 1: Azure portal (GUI)

1. Sign in at <https://portal.azure.com>.
2. Search for **Public IP addresses** and open the service, then click **Create**.
3. Fill in:
   - **Subscription** and **Resource group**: your existing ones
   - **Region**: same as the resource group
   - **Name**: `datacenter-pip`
   - **IP Version**: IPv4
   - **SKU**: Standard
   - **Assignment**: Static
4. Click **Review + create**, then **Create**.
5. Check that `datacenter-pip` appears in the list with an IP address.

## Method 2: Azure CLI

```bash
az login

RG="my-resource-group"      # replace with your resource group name
LOCATION="eastus"           # replace with its region

az network public-ip create \
  --resource-group "$RG" \
  --name datacenter-pip \
  --location "$LOCATION" \
  --sku Standard \
  --allocation-method Static

# Verify
az network public-ip show \
  --resource-group "$RG" \
  --name datacenter-pip \
  --query "{name:name, ip:ipAddress, sku:sku.name, allocation:publicIPAllocationMethod}" -o table
```

> In a shell, `<` and `>` are redirection operators. Never paste placeholders such as `<RG>` as they are: replace them with real values.

## Method 3: Terraform (modules, run from your own machine)

### Project structure

```
azure-public-ip/
├── providers.tf
├── variables.tf
├── main.tf
├── outputs.tf
├── terraform.tfvars        # contains secrets: never commit it
└── modules/
    └── public_ip/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

A module can be reused for every future public IP (only the name changes). The counter-example is copy-pasting a `azurerm_public_ip` block into each project and fixing every copy by hand.

### Module (`modules/public_ip/`)

`variables.tf`
```hcl
variable "name" {
  type        = string
  description = "Name of the public IP"
}

variable "resource_group_name" {
  type        = string
  description = "Existing resource group"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "allocation_method" {
  type    = string
  default = "Static"
}

variable "sku" {
  type    = string
  default = "Standard"
}
```

`main.tf`
```hcl
resource "azurerm_public_ip" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = var.allocation_method
  sku                 = var.sku
}
```

`outputs.tf`
```hcl
output "id" {
  value = azurerm_public_ip.this.id
}

output "ip_address" {
  value = azurerm_public_ip.this.ip_address
}
```

### Root configuration

`providers.tf`
```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}

  # Needed when the Service Principal has no rights at subscription level
  resource_provider_registrations = "none"

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}
```

`variables.tf`
```hcl
variable "resource_group_name" {
  type = string
}

variable "subscription_id" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "client_id" {
  type = string
}

variable "client_secret" {
  type      = string
  sensitive = true
}
```

`main.tf`
```hcl
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

module "datacenter_pip" {
  source = "./modules/public_ip"

  name                = "datacenter-pip"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
}
```

`outputs.tf`
```hcl
output "datacenter_pip_address" {
  value = module.datacenter_pip.ip_address
}
```

`terraform.tfvars` (use your own values, no angle brackets)
```hcl
resource_group_name = "my-resource-group"

subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
client_id       = "00000000-0000-0000-0000-000000000000"
client_secret   = "your-client-secret"
```

`.gitignore`
```gitignore
*.tfvars
.terraform/
*.tfstate
*.tfstate.*
```

### Run

```bash
terraform init
terraform validate
terraform plan      # expect: Plan: 1 to add, 0 to change, 0 to destroy
terraform apply
```

### Where to find the four credentials

| Variable | Where |
|---|---|
| `subscription_id` | Portal → Subscriptions → your subscription → Overview |
| `tenant_id` | Portal → Microsoft Entra ID → Overview |
| `client_id` | Entra ID → App registrations → your app → *Application (client) ID* |
| `client_secret` | Same app → Certificates & secrets → New client secret → copy the **Value** (shown only once) |

Then grant the app the **Contributor** role on the resource group (Resource group → Access control (IAM) → Add role assignment).

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `403 AuthorizationFailed ... register/action` on many providers | `azurerm` 4.x tries to register ~30 Resource Providers on the whole subscription | Add `resource_provider_registrations = "none"` to the provider block |
| `"name" may only contain alphanumeric characters, dash, underscores, parentheses and periods` | The resource group value still contains placeholder characters such as `<` `>` | Use the real resource group name |
| Terraform prompts for variables that are already in your tfvars | The file is not loaded automatically (wrong name such as `terraform.tfvars.txt`, wrong folder) | Name it exactly `terraform.tfvars` in the project root, or pass `-var-file="file.tfvars"` |
| `Invalid client secret` | Secret empty, truncated, or the *Secret ID* was copied instead of the *Value* | Recreate a secret and copy the **Value** |
| `already exists` on apply | The IP was already created with another method | Delete it first (`az network public-ip delete -g "$RG" -n datacenter-pip`) or import it |

## Clean up

```bash
terraform destroy
# or
az network public-ip delete --resource-group "$RG" --name datacenter-pip
```

## Security notes

- Never commit `terraform.tfvars` or the state file: they contain a secret and resource details.
- Prefer short-lived secrets and the least privileged role (Contributor on one resource group, not on the subscription).
- Run the three methods one after the other, deleting the IP in between, since a resource with the same name cannot be created twice.
