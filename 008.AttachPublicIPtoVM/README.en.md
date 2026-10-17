# Attach a Public IP Address to an Azure Virtual Machine: GUI, Azure CLI and Terraform

🌐 **Languages:** [Français](README.fr.md) · **English** · [Deutsch](README.de.md)

## Context

A company is migrating part of its infrastructure to Azure. The migration is split into small, independent tasks to keep risk low and stay in control. This task is one of those steps: **attach an existing public IP address to an existing virtual machine (VM)**, so the VM can be reached from the Internet (administration over SSH or RDP, or a public service).

In this README the resources are called `my-vm` (the VM) and `my-public-ip` (the public IP). Replace them with your own names.

The task is solved three ways:

1. **Azure portal (GUI)**
2. **Azure CLI**
3. **Terraform** (module, run from your own machine, **without** the Azure CLI)

## General procedure: attach a public IP to a VM

These steps apply to any VM, whatever the tool you use.

| Step | What to do | Why |
|---|---|---|
| 1. Understand the target | A public IP is **not** attached to the VM itself, but to the **IP configuration of the VM's network interface (NIC)**, usually named `ipconfig1` | The NIC is the network socket of the VM; the public IP is the address visible from outside plugged into it |
| 2. Check the prerequisites | The public IP exists, is **free** (not associated to anything), is in the **same region** as the NIC, and has the same IP version (IPv4) | Azure refuses an IP that is already in use or in another region |
| 3. Find the NIC and its IP configuration | List the NICs of the VM, then the IP configurations of that NIC | You associate the IP to a specific IP configuration |
| 4. Associate the IP | Portal, CLI or Terraform: link the public IP to the IP configuration | This is the actual attach |
| 5. Verify | The VM shows a public IP address, and the public IP shows the IP configuration it is associated to | Confirms the VM is properly assigned the IP |
| 6. Open the ports if needed | Add a Network Security Group (NSG) rule for SSH (22) or RDP (3389) | A Standard public IP is closed until an NSG allows traffic |

Good to know:

- **No VM stop is needed.** A public IP can be associated while the VM is running. This differs from adding a NIC to a VM, which requires deallocating it.
- One IP configuration holds **one** public IP. A NIC can have several IP configurations.
- A **static** IP keeps its address. A **dynamic** (Basic) IP only receives its address once allocated, so it may show no address while the VM is deallocated.

## Key concepts

| Concept | Example | Counter-example |
|---|---|---|
| Associate to the NIC | `my-public-ip` is linked to `ipconfig1` of the VM's NIC | Looking for an "attach to VM" button: it does not exist, everything happens on the NIC side |
| Free IP | `my-public-ip` is not associated to anything | An IP already associated to another NIC is refused |
| Same region | Public IP and NIC are in the same region | Different regions: the association is refused |
| Associated is not reachable | The VM owns the public address | Ports stay closed until an NSG rule allows them |
| Static allocation | The address never changes, so DNS records stay valid | A dynamic address can change, and DNS then points nowhere |

Why keep the public IP as a separate resource? It can outlive the VM: if the VM is destroyed and recreated, the address (and any firewall rule that references it) stays the same.

## Prerequisites

- An Azure subscription and an **existing resource group** containing the VM and the public IP (note its name).
- For Terraform: Terraform >= 1.5 on your machine (any shell, e.g. Git Bash). The Azure CLI is **not** required.
- For Terraform: a **Service Principal** (client ID + client secret) with the *Contributor* role on the resource group, plus your tenant ID and subscription ID.

> In a shell, `<` and `>` are redirection operators. Never paste placeholders such as `<RG>` as they are: replace them with real values.

## Before you start: check the VM and the public IP

```bash
RG="my-resource-group"      # replace with your resource group name

# The VM must be provisioned, and have no public IP yet
az vm show -d -g "$RG" -n my-vm \
  --query "{provisioning:provisioningState, power:powerState, publicIp:publicIps}" -o table

# NIC of the VM and the name of its IP configuration
NIC=$(az vm nic list -g "$RG" --vm-name my-vm --query "[0].id" -o tsv | awk -F/ '{print $NF}')
echo "NIC = $NIC"
az network nic ip-config list -g "$RG" --nic-name "$NIC" --query "[].{name:name, primary:primary}" -o table

# The public IP must be free: associatedTo must be null
az network public-ip show -g "$RG" -n my-public-ip \
  --query "{ip:ipAddress, sku:sku.name, allocation:publicIPAllocationMethod, region:location, associatedTo:ipConfiguration.id}" -o json
```

Expected: `Succeeded`, `VM running`, an empty `publicIp`, an IP configuration name (probably `ipconfig1`), and `associatedTo` set to `null`.

## Method 1: Azure portal (GUI)

1. Sign in at <https://portal.azure.com>.
2. **Virtual machines** → your VM → **Networking** (or **Network settings**): note the NIC name.
3. **Public IP addresses** → `my-public-ip` → **Overview** → **Associate**.
4. **Resource type**: **Network interface**; **Resource**: the VM's NIC; **IP configuration**: `ipconfig1` → **OK**.
5. Check: on the VM **Overview**, the **Public IP address** field shows the address of `my-public-ip`.

Alternative path: **Network interfaces** → your NIC → **IP configurations** → `ipconfig1` → **Public IP address**: **Associate** → choose `my-public-ip` → **Save**.

## Method 2: Azure CLI

```bash
RG="my-resource-group"

NIC=$(az vm nic list -g "$RG" --vm-name my-vm --query "[0].id" -o tsv | awk -F/ '{print $NF}')
IPCONFIG=$(az network nic ip-config list -g "$RG" --nic-name "$NIC" --query "[0].name" -o tsv)

az network nic ip-config update \
  -g "$RG" \
  --nic-name "$NIC" \
  -n "$IPCONFIG" \
  --public-ip-address my-public-ip
```

If the public IP lives in another resource group, pass its **full ID** to `--public-ip-address`.

## Method 3: Terraform

### Two situations

**New deployment (you create the NIC with Terraform).** This is the normal case: reference the public IP in the NIC's IP configuration.

```hcl
resource "azurerm_public_ip" "this" {
  name                = "my-public-ip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "this" {
  name                = "my-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id   # the association
  }
}
```

**Existing VM and existing public IP (this task).** `azurerm` has no dedicated "associate a public IP to an existing NIC" resource: the IP is a property of the NIC's IP configuration. Managing the NIC with `azurerm_network_interface` would mean importing it and copying its settings. A lighter approach is the `azapi` provider, which sends **only** the IP configuration change to the Azure API. The rest of this section uses it. The VM can stay running.

Why a module? A module is reusable (only its inputs change). The counter-example is copy-pasting the same resource block into every project.

### Project structure

```
attach-public-ip/
├── providers.tf
├── variables.tf
├── main.tf                     # root: contains module "nic_public_ip"
├── outputs.tf
├── terraform.tfvars            # contains secrets: never commit it
├── .gitignore
└── modules/
    └── nic_public_ip/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### `providers.tf`

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
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

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}
```

### `variables.tf`

```hcl
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

variable "resource_group_name" {
  type = string
}

variable "vm_name" {
  type    = string
  default = "my-vm"
}

variable "public_ip_name" {
  type    = string
  default = "my-public-ip"
}
```

### `main.tf` (root)

```hcl
# Existing VM: read, not managed
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

# Existing public IP to associate
data "azurerm_public_ip" "pip" {
  name                = var.public_ip_name
  resource_group_name = var.resource_group_name
}

# NICs of the VM, read through the Azure API
data "azapi_resource" "vm" {
  type                   = "Microsoft.Compute/virtualMachines@2024-03-01"
  resource_id            = data.azurerm_virtual_machine.vm.id
  response_export_values = ["properties.networkProfile.networkInterfaces"]
}

locals {
  # The first NIC of the VM is the primary one
  nic_id = data.azapi_resource.vm.output.properties.networkProfile.networkInterfaces[0].id
}

# Current IP configuration of that NIC
data "azapi_resource" "nic" {
  type                   = "Microsoft.Network/networkInterfaces@2024-01-01"
  resource_id            = local.nic_id
  response_export_values = ["properties.ipConfigurations"]
}

module "nic_public_ip" {
  source = "./modules/nic_public_ip"

  nic_id           = local.nic_id
  ip_configuration = data.azapi_resource.nic.output.properties.ipConfigurations[0]
  public_ip_id     = data.azurerm_public_ip.pip.id
}
```

### `outputs.tf`

```hcl
output "public_ip_address" {
  value = data.azurerm_public_ip.pip.ip_address
}

output "nic_id" {
  value = local.nic_id
}
```

### `modules/nic_public_ip/variables.tf`

```hcl
variable "nic_id" {
  type        = string
  description = "ID of the existing NIC"
}

variable "ip_configuration" {
  type        = any
  description = "Current IP configuration of the NIC (read through the Azure API)"
}

variable "public_ip_id" {
  type        = string
  description = "ID of the public IP to associate"
}
```

### `modules/nic_public_ip/main.tf`

```hcl
terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

locals {
  ipc   = var.ip_configuration
  props = local.ipc.properties

  # privateIPAddress is only kept when the allocation is Static
  static_private_ip = {
    for k, v in { privateIPAddress = try(local.props.privateIPAddress, "") } :
    k => v if local.props.privateIPAllocationMethod == "Static"
  }
}

resource "azapi_update_resource" "this" {
  type        = "Microsoft.Network/networkInterfaces@2024-01-01"
  resource_id = var.nic_id

  body = {
    properties = {
      ipConfigurations = [
        {
          name = local.ipc.name
          properties = merge(
            {
              subnet                    = { id = local.props.subnet.id }
              privateIPAllocationMethod = local.props.privateIPAllocationMethod
              primary                   = try(local.props.primary, true)
              publicIPAddress           = { id = var.public_ip_id }
            },
            local.static_private_ip
          )
        }
      ]
    }
  }
}
```

### `modules/nic_public_ip/outputs.tf`

```hcl
output "nic_id" {
  value = azapi_update_resource.this.resource_id
}
```

### `terraform.tfvars` (your own values, no angle brackets)

```hcl
resource_group_name = "my-resource-group"

subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
client_id       = "00000000-0000-0000-0000-000000000000"
client_secret   = "your-client-secret"
```

### `.gitignore`

```gitignore
*.tfvars
.terraform/
*.tfstate
*.tfstate.*
```

### Where to find the four credentials

| Variable | Where |
|---|---|
| `subscription_id` | Portal → Subscriptions → your subscription → Overview |
| `tenant_id` | Portal → Microsoft Entra ID → Overview |
| `client_id` | Entra ID → App registrations → your app → *Application (client) ID* |
| `client_secret` | Same app → Certificates & secrets → New client secret → copy the **Value** (shown only once) |

Then grant the app the **Contributor** role on the resource group (Resource group → Access control (IAM) → Add role assignment). If your environment provides ready-made credentials, use those instead; they may change with every session.

### Run (the VM can stay running)

```bash
terraform init
terraform validate
terraform plan      # expect: Plan: 1 to add, 0 to change, 0 to destroy
terraform apply
```

Notes:

- The `main.tf` that contains `module "nic_public_ip"` is the one at the **root** of the folder, not the one inside `modules/`.
- The module changes the **first** IP configuration of the **first** NIC of the VM, which is the standard case. For a NIC with several IP configurations, target the right one.

## Final check (all methods)

```bash
# The VM exposes the public IP
az vm show -d -g "$RG" -n my-vm \
  --query "{publicIp:publicIps, provisioning:provisioningState, power:powerState}" -o table

# associatedTo must end with .../networkInterfaces/<NIC>/ipConfigurations/<ipconfig>
az network public-ip show -g "$RG" -n my-public-ip \
  --query "{ip:ipAddress, associatedTo:ipConfiguration.id}" -o json

# NIC side
az network nic ip-config show -g "$RG" --nic-name "$NIC" -n "$IPCONFIG" \
  --query "publicIPAddress.id" -o tsv
```

Expected: `publicIp` filled in (same address as `ip`), `associatedTo` not empty, and an ID ending with `my-public-ip`.

## Reset (to try another method)

```bash
az network nic ip-config update -g "$RG" --nic-name "$NIC" -n "$IPCONFIG" --remove publicIpAddress
```

(Or portal: **Public IP addresses → my-public-ip → Dissociate**.) Also delete the local state of the previous attempt (`rm -f terraform.tfstate*`), otherwise Terraform believes the association is already done. `terraform destroy` does **not** dissociate the IP: this resource only sends a modification and cannot undo it.

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| Public IP already in use | `my-public-ip` is associated to another NIC | Check `associatedTo`, dissociate it first |
| Region error | Public IP and NIC are in different regions | They must share the region |
| `publicIp` empty although the association is done | Dynamic IP on a deallocated VM | Start the VM, or use a static IP |
| SSH or RDP refused despite the public IP | No NSG rule allows the port | Add an NSG rule for the port |
| `403 AuthorizationFailed ... register/action` on many providers | `azurerm` 4.x tries to register ~30 Resource Providers on the whole subscription | Add `resource_provider_registrations = "none"` to the provider block |
| Same error, or an authentication error, with an empty `providers.tf` | Without the provider block, the credentials are ignored | Fill in `providers.tf` |
| Terraform prompts for variables that are already in your tfvars | The file is not loaded automatically (wrong name such as `terraform.tfvars.txt`, wrong folder) | Name it exactly `terraform.tfvars`, next to `main.tf`, or pass `-var-file="file.tfvars"` |
| `Invalid client secret` | Secret empty, truncated, or the *Secret ID* copied instead of the *Value* | Recreate a secret and copy the **Value** |
| `Module not installed` | `terraform init` was not run | Run `terraform init` |
| `No declaration found for var.xxx`, or red underlines in VS Code | A root `variables.tf` is missing, or the editor has not reloaded | Check the files with `find`, run `terraform init` and `terraform validate`; if valid, run **Developer: Reload Window** |
| Error on `.output.properties...` | The `azapi` output has a different shape | Print the NIC with `az network nic show -o json` and adapt the path |
| Type error on `merge` or `ip_configuration` | Unusual NIC (several IP configurations, IPv6) | Target the right IP configuration explicitly |
| `ResourceNotFound` on a `data` source | Wrong resource group name, or the VM is still being created | Check the names and wait for `provisioningState = Succeeded` |
| Old state or old credentials after a new session | The state file and credentials belong to a previous environment | Use a fresh folder and the credentials of the current session |

## Clean up

```bash
# CLI
az network nic ip-config update -g "$RG" --nic-name "$NIC" -n "$IPCONFIG" --remove publicIpAddress
```

`terraform destroy` does not dissociate the IP (see above).

## Security notes

- Never commit `terraform.tfvars` or state files: they contain a secret and resource details.
- Prefer short-lived secrets and the least privileged role (Contributor on one resource group, not on the subscription).
- A public IP exposes the VM to the Internet: only open the ports you need in the NSG, and prefer key-based SSH.
- Run the three methods one after the other and undo the change in between: an IP configuration holds only one public IP.
