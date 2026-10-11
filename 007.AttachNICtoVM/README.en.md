# Attach a Network Interface (NIC) to an Azure Virtual Machine: GUI, Azure CLI and Terraform

🌐 **Languages:** [Français](README.fr.md) · **English** · [Deutsch](README.de.md)

## Context

A company is migrating part of its infrastructure to Azure. To keep risk low and stay in control, the migration is split into small, independent tasks instead of one big move. This task is one of those steps: **attach an existing network interface (NIC) to an existing virtual machine (VM)**.

**Goal:** attach the NIC `datacenter-nic` to the VM `datacenter-vm`, make sure the NIC shows as attached, and make sure the VM has finished initializing.

The task is solved three ways:

1. **Azure portal (GUI)**
2. **Azure CLI**
3. **Terraform** (module, run from your own machine, **without** the Azure CLI)

## ⚠️ Mandatory first step: stop **and deallocate** the VM

Azure cannot add a NIC to a running VM. The VM must be **deallocated** before the attach, then started again afterwards.

| | Example | Counter-example |
|---|---|---|
| Deallocated | Portal **Stop** button, or `az vm deallocate`: status `Stopped (deallocated)`, compute released | Shutting the VM down from inside the OS, or `az vm stop`: the VM is stopped but **still allocated**, so the attach still fails |
| Running VM | A data disk can be attached hot | The attach of a NIC is refused |

Order to follow: **deallocate → attach → start → verify**.

## Key concepts

| Concept | Example | Counter-example |
|---|---|---|
| Attach an existing NIC | `datacenter-nic` already exists: you only link it to `datacenter-vm` | Creating a new NIC leaves you with an extra card |
| Primary vs secondary NIC | The original NIC stays primary; `datacenter-nic` is added as secondary | "Replacing" the primary NIC is not what is asked |
| Same region and same VNet | Both are in the same region and the same virtual network | A NIC from another VNet or region is refused |
| Attached is not configured in the OS | Azure reports the NIC as attached | The interface still has to be configured inside the OS (out of scope) |

Why do it? A VM with two NICs separates traffic: for example one NIC for user traffic and one for administration or backups, each with its own Network Security Group rules. It is also common for virtual firewalls and proxies.

## Prerequisites

- An Azure subscription and an **existing resource group** containing the VM and the NIC (note its name).
- The VM size must allow two NICs.
- For Terraform: Terraform >= 1.5 on your machine (any shell, e.g. Git Bash). The Azure CLI is **not** required.
- For Terraform: a **Service Principal** (client ID + client secret) with the *Contributor* role on the resource group, plus your tenant ID and subscription ID.

> In a shell, `<` and `>` are redirection operators. Never paste placeholders such as `<RG>` as they are: replace them with real values.

## Before you start: check the VM and the NIC

```bash
RG="my-resource-group"      # replace with your resource group name

# The VM must be provisioned and running
az vm show -d -g "$RG" -n datacenter-vm \
  --query "{provisioning:provisioningState, power:powerState, size:hardwareProfile.vmSize}" -o table

# NICs already on the VM (the first one is the primary)
az vm nic list -g "$RG" --vm-name datacenter-vm -o table

# The NIC must be free: vm must be null
az network nic show -g "$RG" -n datacenter-nic \
  --query "{vm:virtualMachine.id, region:location}" -o json
```

Then deallocate the VM:

```bash
az vm deallocate -g "$RG" -n datacenter-vm
```

(Portal: **Virtual machines → datacenter-vm → Stop**, then wait for **Stopped (deallocated)**.)

## Method 1: Azure portal (GUI)

1. Sign in at <https://portal.azure.com>.
2. Stop the VM and wait for **Stopped (deallocated)**.
3. **Networking** (or **Network settings**) → **Attach network interface**. The button is greyed out while the VM is running.
4. Choose `datacenter-nic` → **OK**.
5. **Overview** → **Start**, and wait for **Running**.
6. Check: `datacenter-nic` appears under **Networking**, and on the NIC the **Virtual machine** field shows `datacenter-vm`.

## Method 2: Azure CLI

```bash
az vm deallocate -g "$RG" -n datacenter-vm
az vm nic add -g "$RG" --vm-name datacenter-vm --nics datacenter-nic
az vm start -g "$RG" -n datacenter-vm
```

If the NIC lives in another resource group, pass its **full ID** to `--nics`.

## Method 3: Terraform

### Why this needs a special approach

Terraform's `azurerm` provider has no dedicated "attach a NIC to a VM" resource: the list of NICs is a property of the VM itself. Managing the VM with `azurerm_linux_virtual_machine` would mean importing it and copying all its settings (size, image, SSH key…), with a risk of replacing it. A lighter approach is the `azapi` provider, which sends **only** the `networkProfile` change to the Azure API.

Two details learned the hard way:

- The `azurerm_virtual_machine` data source does **not** export `network_interface_ids`. The current NICs are read with an `azapi_resource` data source instead.
- `azapi` does **not** deallocate the VM for you: do it before `terraform apply`.

Why a module? A module is reusable (only its inputs change). The counter-example is copy-pasting the same resource block into every project.

### Project structure

```
attach-nic/
├── providers.tf
├── variables.tf
├── main.tf                     # root: contains module "nic_attachment"
├── outputs.tf
├── terraform.tfvars            # contains secrets: never commit it
├── .gitignore
└── modules/
    └── vm_nic_attachment/
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
  default = "datacenter-vm"
}

variable "nic_name" {
  type    = string
  default = "datacenter-nic"
}
```

### `main.tf` (root)

```hcl
# Existing VM: read, not managed
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

# NICs currently attached to the VM, read through the Azure API
data "azapi_resource" "vm" {
  type                   = "Microsoft.Compute/virtualMachines@2024-03-01"
  resource_id            = data.azurerm_virtual_machine.vm.id
  response_export_values = ["properties.networkProfile.networkInterfaces"]
}

# Existing NIC to attach
data "azurerm_network_interface" "new" {
  name                = var.nic_name
  resource_group_name = var.resource_group_name
}

locals {
  # The first NIC of the list is the primary one
  primary_nic_id = data.azapi_resource.vm.output.properties.networkProfile.networkInterfaces[0].id
}

module "nic_attachment" {
  source = "./modules/vm_nic_attachment"

  vm_id              = data.azurerm_virtual_machine.vm.id
  primary_nic_id     = local.primary_nic_id
  additional_nic_ids = [data.azurerm_network_interface.new.id]
}
```

### `outputs.tf`

```hcl
output "attached_nic_ids" {
  value = module.nic_attachment.nic_ids
}
```

### `modules/vm_nic_attachment/variables.tf`

```hcl
variable "vm_id" {
  type        = string
  description = "ID of the existing VM"
}

variable "primary_nic_id" {
  type        = string
  description = "Primary NIC already attached"
}

variable "additional_nic_ids" {
  type        = list(string)
  description = "Additional NICs to attach"
}
```

### `modules/vm_nic_attachment/main.tf`

```hcl
terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

resource "azapi_update_resource" "this" {
  type        = "Microsoft.Compute/virtualMachines@2024-03-01"
  resource_id = var.vm_id

  body = {
    properties = {
      networkProfile = {
        networkInterfaces = concat(
          [{ id = var.primary_nic_id, properties = { primary = true } }],
          [for id in var.additional_nic_ids : { id = id, properties = { primary = false } }]
        )
      }
    }
  }
}
```

### `modules/vm_nic_attachment/outputs.tf`

```hcl
output "nic_ids" {
  value = concat([var.primary_nic_id], var.additional_nic_ids)
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

### Run, with the VM **already deallocated**

```bash
terraform init
terraform validate
terraform plan      # expect: Plan: 1 to add, 0 to change, 0 to destroy
terraform apply

# then start the VM again
az vm start -g "$RG" -n datacenter-vm      # or Portal: Overview → Start
```

Note: the `main.tf` that contains `module "nic_attachment"` is the one at the **root** of the folder, not the one inside `modules/`.

## Final check (all methods)

```bash
# Two NICs listed
az vm nic list -g "$RG" --vm-name datacenter-vm -o table

# The ID must end with datacenter-vm
az network nic show -g "$RG" -n datacenter-nic --query "virtualMachine.id" -o tsv

# Initialization completed: Succeeded and VM running
az vm show -d -g "$RG" -n datacenter-vm \
  --query "{provisioning:provisioningState, power:powerState}" -o table
```

Only submit the task once you see `Succeeded` and `VM running`.

## Reset (to try another method)

```bash
az vm deallocate -g "$RG" -n datacenter-vm
az vm nic remove -g "$RG" --vm-name datacenter-vm --nics datacenter-nic
```

Also delete the local state of the previous attempt (`rm -f terraform.tfstate*`), otherwise Terraform believes the attach is already done. `terraform destroy` does **not** detach the NIC: this resource only sends a modification and cannot undo it.

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| NIC attach refused, button greyed out | The VM is running, or only stopped but still allocated | **Deallocate** the VM (status `Stopped (deallocated)`) |
| NIC already in use | The NIC is attached to another VM | Check `virtualMachine.id`, detach it first |
| Region or VNet error | NIC and VM are in different regions or virtual networks | They must share region and VNet |
| Error on the number of NICs | The VM size does not allow two NICs | Use a larger size |
| `403 AuthorizationFailed ... register/action` on many providers | `azurerm` 4.x tries to register ~30 Resource Providers on the whole subscription | Add `resource_provider_registrations = "none"` to the provider block |
| Same error, or an authentication error, with an empty `providers.tf` | Without the provider block, the credentials are ignored | Fill in `providers.tf` |
| `"name" may only contain alphanumeric characters, dash, underscores, parentheses and periods` | The resource group value still contains placeholder characters such as `<` `>` | Use the real resource group name |
| Terraform prompts for variables that are already in your tfvars | The file is not loaded automatically (wrong name such as `terraform.tfvars.txt`, wrong folder) | Name it exactly `terraform.tfvars`, next to `main.tf`, or pass `-var-file="file.tfvars"` |
| `Invalid client secret` | Secret empty, truncated, or the *Secret ID* copied instead of the *Value* | Recreate a secret and copy the **Value** |
| `Module not installed` | `terraform init` was not run | Run `terraform init` |
| `No declaration found for var.xxx`, or red underlines in VS Code | A root `variables.tf` is missing, or the editor has not reloaded | Check the files with `find`, run `terraform init` and `terraform validate`; if valid, run **Developer: Reload Window** |
| `Unsupported attribute ... network_interface_ids` | The `azurerm_virtual_machine` data source does not export it | Read the NICs with the `azapi_resource` data source |
| `ResourceNotFound` on a `data` source | Wrong resource group name, or the VM is still being created | Check the names and wait for `provisioningState = Succeeded` |
| Old state or old credentials after a new session | The state file and credentials belong to a previous environment | Use a fresh folder and the credentials of the current session |

## Clean up

```bash
# CLI (VM deallocated first)
az vm nic remove --resource-group "$RG" --vm-name datacenter-vm --nics datacenter-nic
```

`terraform destroy` does not detach a NIC (see above).

## Security notes

- Never commit `terraform.tfvars` or state files: they contain a secret and resource details.
- Prefer short-lived secrets and the least privileged role (Contributor on one resource group, not on the subscription).
- Run the three methods one after the other and undo the change in between: a NIC cannot be attached twice.
- In a real project, create the VM with Terraform and list both NICs in `network_interface_ids` from the start: no import and no deallocation needed.
