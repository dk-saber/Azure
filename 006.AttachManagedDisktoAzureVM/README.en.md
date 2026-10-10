# Azure Migration Tasks: GUI, Azure CLI and Terraform

🌐 **Languages:** [Français](README.fr.md) · **English** · [Deutsch](README.de.md)

## Context

A company is migrating part of its infrastructure to Azure. To keep risk low and stay in control, the migration is split into small, independent tasks instead of one big move. Each task below is solved three ways:

1. **Azure portal (GUI)**
2. **Azure CLI**
3. **Terraform** (modules, run from your own machine, **without** the Azure CLI)

| # | Task | Resources |
|---|---|---|
| 1 | [Create a public IP address](#task-1-create-a-public-ip-address) | `datacenter-pip` |
| 2 | [Attach a managed disk to a virtual machine](#task-2-attach-a-managed-disk-to-a-virtual-machine) | `datacenter-vm`, `datacenter-disk` |

## Prerequisites

- An Azure subscription and an **existing resource group** (note its name and region).
- For Terraform: Terraform >= 1.5 on your machine. The Azure CLI is **not** required.
- For Terraform: a **Service Principal** (client ID + client secret) with the *Contributor* role on the resource group, plus your tenant ID and subscription ID.

> In a shell, `<` and `>` are redirection operators. Never paste placeholders such as `<RG>` as they are: replace them with real values.

## Common Terraform setup

Give each task its own folder, so each has its own state file:

```
azure-migration/
├── task-01-public-ip/
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── terraform.tfvars        # contains secrets: never commit it
│   └── modules/public_ip/
├── task-02-attach-disk/
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── terraform.tfvars
│   └── modules/disk_attachment/
└── .gitignore
```

Why modules? A module is reusable (only its inputs change). The counter-example is copy-pasting the same resource block into every project and fixing each copy by hand.

### `providers.tf` (identical in every task folder)

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

### Authentication variables (add to every `variables.tf`)

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

### Run (in each task folder)

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

---

## Task 1: Create a public IP address

**Goal:** create a public IP address named `datacenter-pip` in an existing resource group.

### Key concepts

| Concept | Example | Counter-example |
|---|---|---|
| Public vs private IP | `20.50.10.4` can be reached from the Internet (e.g. SSH) | `10.0.0.4` is only reachable inside the Azure network |
| Static allocation | The address never changes, even if the VM is stopped, so DNS records stay valid | A dynamic address can change after a stop/start and DNS then points nowhere |
| Standard SKU | Secure by default (closed until a Network Security Group allows traffic) | The Basic SKU is retired by Azure (since 30 September 2025): do not use it |

Why create the IP separately from the VM? It can outlive the VM: if the VM is destroyed and recreated, the address (and any firewall rule that references it) stays the same.

### Method 1: Azure portal (GUI)

1. Sign in at <https://portal.azure.com>.
2. Search for **Public IP addresses**, open the service, click **Create**.
3. Fill in:
   - **Subscription** and **Resource group**: your existing ones
   - **Region**: same as the resource group
   - **Name**: `datacenter-pip`
   - **IP Version**: IPv4
   - **SKU**: Standard
   - **Assignment**: Static
4. Click **Review + create**, then **Create**.
5. Check that `datacenter-pip` appears in the list with an IP address.

### Method 2: Azure CLI

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

### Method 3: Terraform (`task-01-public-ip/`)

`modules/public_ip/variables.tf`
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

`modules/public_ip/main.tf`
```hcl
resource "azurerm_public_ip" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = var.allocation_method
  sku                 = var.sku
}
```

`modules/public_ip/outputs.tf`
```hcl
output "id" {
  value = azurerm_public_ip.this.id
}

output "ip_address" {
  value = azurerm_public_ip.this.ip_address
}
```

`variables.tf` (plus the authentication variables above)
```hcl
variable "resource_group_name" {
  type = string
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

Expected plan: `Plan: 1 to add, 0 to change, 0 to destroy`.

---

## Task 2: Attach a managed disk to a virtual machine

**Goal:** attach the existing managed disk `datacenter-disk` to the existing VM `datacenter-vm` (region `eastus`) as a **data disk**, once the VM has finished initializing.

### Key concepts

| Concept | Example | Counter-example |
|---|---|---|
| Attach an existing disk | `datacenter-disk` already exists: you only link it to `datacenter-vm` | "Create and attach" builds a **new** empty disk, which is not what is asked |
| Data disk vs OS disk | A data disk holds a database or logs | The OS disk holds the system and is created with the VM |
| LUN | Each data disk has a unique number (0, 1, 2…) on the VM | Two disks with the same LUN: Azure refuses |
| Attached is not usable yet | After attaching, the disk shows up inside the VM | It is not partitioned, formatted or mounted yet: that is done inside the OS |

Why do it? Data placed on a dedicated disk **outlives the VM**. You can destroy, resize or replace the VM without losing data: detach the disk and attach it to another VM.

### Before you start: check the VM and the disk

```bash
RG="my-resource-group"

# The VM must be provisioned and running (initialization completed)
az vm show -d -g "$RG" -n datacenter-vm \
  --query "{provisioning:provisioningState, power:powerState}" -o table

# The disk must be free: managedBy must be empty
az disk show -g "$RG" -n datacenter-disk \
  --query "{state:diskState, region:location, attachedTo:managedBy}" -o table
```

Expected: `Succeeded`, `VM running`, and a disk in state `Unattached` in `eastus`.

### Method 1: Azure portal (GUI)

1. Open **Virtual machines** → `datacenter-vm`.
2. On **Overview**, check that the status is **Running**.
3. Left menu: **Settings → Disks**.
4. Under **Data disks**, click **Attach existing disks**.
5. In the new row set **LUN** `0` and **Disk name** `datacenter-disk`; keep the default **Host caching**.
6. Click **Save** at the top of the page. Without it nothing is attached, even if the disk shows in the form.
7. Check that `datacenter-disk` is listed among the data disks.

### Method 2: Azure CLI

```bash
az vm disk attach \
  --resource-group "$RG" \
  --vm-name datacenter-vm \
  --name datacenter-disk

# Verify on the VM side
az vm show -g "$RG" -n datacenter-vm \
  --query "storageProfile.dataDisks[].{name:name, lun:lun, caching:caching}" -o table

# Verify on the disk side: state Attached and managedBy = the VM
az disk show -g "$RG" -n datacenter-disk \
  --query "{state:diskState, attachedTo:managedBy}" -o table
```

If the disk lives in another resource group than the VM, pass its **full ID** to `--name` (`az disk show ... --query id -o tsv`).

### Method 3: Terraform (`task-02-attach-disk/`)

The VM and the disk already exist: they are **read** with `data` sources, and only the attachment is created.

`modules/disk_attachment/variables.tf`
```hcl
variable "virtual_machine_id" {
  type        = string
  description = "ID of the target VM"
}

variable "managed_disk_id" {
  type        = string
  description = "ID of the existing managed disk"
}

variable "lun" {
  type        = number
  default     = 0
  description = "Logical unit number, unique per VM"
}

variable "caching" {
  type    = string
  default = "ReadWrite"
}

variable "create_option" {
  type        = string
  default     = "Attach"
  description = "Attach = link an existing disk"
}
```

`modules/disk_attachment/main.tf`
```hcl
resource "azurerm_virtual_machine_data_disk_attachment" "this" {
  virtual_machine_id = var.virtual_machine_id
  managed_disk_id    = var.managed_disk_id
  lun                = var.lun
  caching            = var.caching
  create_option      = var.create_option
}
```

`modules/disk_attachment/outputs.tf`
```hcl
output "id" {
  value = azurerm_virtual_machine_data_disk_attachment.this.id
}
```

`variables.tf` (plus the authentication variables above)
```hcl
variable "resource_group_name" {
  type = string
}

variable "vm_name" {
  type    = string
  default = "datacenter-vm"
}

variable "disk_name" {
  type    = string
  default = "datacenter-disk"
}
```

`main.tf`
```hcl
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

data "azurerm_managed_disk" "disk" {
  name                = var.disk_name
  resource_group_name = var.resource_group_name
}

module "datacenter_disk_attachment" {
  source = "./modules/disk_attachment"

  virtual_machine_id = data.azurerm_virtual_machine.vm.id
  managed_disk_id    = data.azurerm_managed_disk.disk.id
  lun                = 0
}
```

`outputs.tf`
```hcl
output "attachment_id" {
  value = module.datacenter_disk_attachment.id
}
```

Expected plan: `Plan: 1 to add, 0 to change, 0 to destroy`. If the VM or the disk appears among the resources to create, a `data` block was replaced by a `resource` block: stop and fix it.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `403 AuthorizationFailed ... register/action` on many providers | `azurerm` 4.x tries to register ~30 Resource Providers on the whole subscription | Add `resource_provider_registrations = "none"` to the provider block |
| Same error, or an authentication error, with an empty `providers.tf` | Without the provider block, the credentials are ignored | Fill in `providers.tf` in every task folder |
| `"name" may only contain alphanumeric characters, dash, underscores, parentheses and periods` | The resource group value still contains placeholder characters such as `<` `>` | Use the real resource group name |
| Terraform prompts for variables that are already in your tfvars | The file is not loaded automatically (wrong name such as `terraform.tfvars.txt`, wrong folder) | Name it exactly `terraform.tfvars` in the task folder, or pass `-var-file="file.tfvars"` |
| `Invalid client secret` | Secret empty, truncated, or the *Secret ID* copied instead of the *Value* | Recreate a secret and copy the **Value** |
| `already exists` on apply (task 1) | The IP was already created with another method | Delete it first or import it |
| `Disk ... is already attached to VM ...` (task 2) | The disk is attached to another VM | Check `managedBy`, detach it first |
| Zone or region error (task 2) | Disk and VM are in different regions or availability zones | Both must share the region and the zone |
| `LUN ... already in use` (task 2) | Another disk already uses that LUN | Pick another number |
| `ResourceNotFound` on a `data` source | Wrong resource group name, or the VM is still being created | Check the names and wait for `provisioningState = Succeeded` |
| Old state or old credentials after a new session | The state file and credentials belong to a previous environment | Use a fresh task folder and the credentials of the current session |

## Clean up

```bash
# Terraform: in the task folder
terraform destroy

# Task 1 with the CLI
az network public-ip delete --resource-group "$RG" --name datacenter-pip

# Task 2 with the CLI
az vm disk detach --resource-group "$RG" --vm-name datacenter-vm --name datacenter-disk
```

## Security notes

- Never commit `terraform.tfvars` or state files: they contain a secret and resource details.
- Prefer short-lived secrets and the least privileged role (Contributor on one resource group, not on the subscription).
- Run the three methods one after the other and undo the change in between: a resource cannot be created twice, and a disk cannot be attached twice.
