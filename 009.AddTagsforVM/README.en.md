# Add and Manage Tags on an Azure Virtual Machine: GUI, Azure CLI and Terraform

🌐 **Languages:** [Français](README.fr.md) · **English** · [Deutsch](README.de.md)

## Context

A company is migrating part of its infrastructure to Azure. During the migration, several virtual machines (VMs) were created in different regions, and some are not tagged properly. This task is one of the clean-up steps: **add the tag `Environment=dev` to an existing VM**.

In this README the VM is called `my-vm`. Replace it with your own name.

The task is solved three ways:

1. **Azure portal (GUI)**
2. **Azure CLI**
3. **Terraform** (module, run from your own machine, **without** the Azure CLI)

## What is a tag and why use it

A **tag** is a key/value label attached to an Azure resource, here `Environment` = `dev`. It does not change how the VM behaves: it is used to classify, find and bill resources.

| Concept | Example | Counter-example |
|---|---|---|
| Azure tag | `Environment=dev` on the resource `my-vm`: visible in the portal, in cost reports and in policies | A label written in a file inside the VM: Azure cannot see it |
| Add (merge) | You add `Environment=dev` and the existing tags (`Owner`, `Project`…) stay | A command that **replaces**: every previous tag disappears |
| Exact value | `Environment=dev` | `Environment=Dev`: the tag **name** is not case-sensitive, but the **value** is, so it is not the same label for a check |
| No inheritance | The tag is on the VM | A tag on the resource group is not copied to the VM, and a tag on the VM is not copied to its NIC or disks |

Real-world use:

- **Cost allocation**: a Cost Management report grouped by `Environment` separates dev, test and production.
- **Governance**: an Azure Policy can require a tag, or an automation can shut down every `Environment=dev` VM at night.
- **Findability**: filter the resource list by tag.

## General procedure: tag a VM

These steps apply to any VM, whatever the tool you use.

| Step | What to do | Why |
|---|---|---|
| 1. Find the VM | Search the VM by name across regions to get its resource group | VMs of the same migration can sit in different regions |
| 2. Read the current tags | Display the tags already on the VM | You must be able to check later that none was lost |
| 3. Add the tag with a **merge** | Portal **Tags** blade, `az tag update --operation merge`, or Terraform | Merge keeps the existing tags |
| 4. Verify | Display the tags again | Confirms `Environment=dev` is present and the others are intact |

Good to know:

- Adding a tag **does not restart** the VM and does not affect its operation.
- A tag name cannot contain `<`, `>`, `%`, `&`, `\`, `?` or `/`.
- A resource holds at most 50 tags.

## Prerequisites

- An Azure subscription and the **resource group** that contains the VM (note its name).
- For Terraform: Terraform >= 1.5 on your machine (any shell, e.g. Git Bash). The Azure CLI is **not** required.
- For Terraform: a **Service Principal** (client ID + client secret) with the *Contributor* role on the resource group, plus your tenant ID and subscription ID.

> In a shell, `<` and `>` are redirection operators. Never paste placeholders such as `<RG>` as they are: replace them with real values.

## Before you start: find the VM and its tags

```bash
# The VM can be in any region: search it by name
az vm list --query "[?name=='my-vm'].{group:resourceGroup, region:location}" -o table

RG="my-resource-group"      # value of the "group" column, no angle brackets

# Current tags (null or {} if none)
az vm show -g "$RG" -n my-vm --query tags -o json
```

Write down the existing tags: at the end, they must **all** still be there.

## Method 1: Azure portal (GUI)

1. Sign in at <https://portal.azure.com>.
2. **Virtual machines** → `my-vm`.
3. Left menu: **Tags**.
4. In the first empty row: **Name** = `Environment`, **Value** = `dev`.
5. Click **Apply** at the bottom of the page. Without it nothing is saved.
6. Check: the **Tags** page (or **Overview**) shows `Environment : dev`.

## Method 2: Azure CLI

```bash
RG="my-resource-group"

VM_ID=$(az vm show -g "$RG" -n my-vm --query id -o tsv)

az tag update --resource-id "$VM_ID" --operation merge --tags Environment=dev
```

`--operation merge` adds the tag **without erasing** the others.

Equivalent variant with `az vm update`:

```bash
az vm update -g "$RG" -n my-vm --set tags.Environment=dev
```

**Avoid**: `az resource tag --tags Environment=dev ...` without `--is-incremental` **replaces** all existing tags with this single one.

## Method 3: Terraform

### Two situations

**New deployment (you create the VM with Terraform).** This is the normal case: set `tags` on the VM resource.

```hcl
resource "azurerm_linux_virtual_machine" "this" {
  name                = "my-vm"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  # ... size, image, network interfaces, credentials ...

  tags = {
    Environment = "dev"
  }
}
```

**Existing VM (this task).** `tags` is a property of the VM itself. Managing the VM with `azurerm_linux_virtual_machine` would mean importing it and copying all its settings (size, image, SSH key…), with a risk of replacing it. A lighter approach is the `azapi` provider, which sends **only** the tags change to the Azure API. The provider merges the request body with the existing resource, so the other tags should stay: compare `az vm show --query tags` before and after. The rest of this section uses it.

Why a module? A module is reusable (only its inputs change). The counter-example is copy-pasting the same resource block into every project.

### Project structure

```
tag-vm/
├── providers.tf
├── variables.tf
├── main.tf                     # root: contains module "vm_tags"
├── outputs.tf
├── terraform.tfvars            # contains secrets: never commit it
├── .gitignore
└── modules/
    └── vm_tags/
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

variable "tags" {
  type = map(string)
  default = {
    Environment = "dev"
  }
}
```

### `main.tf` (root)

```hcl
# Existing VM: read, not managed
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

module "vm_tags" {
  source = "./modules/vm_tags"

  vm_id = data.azurerm_virtual_machine.vm.id
  tags  = var.tags
}
```

### `outputs.tf`

```hcl
output "vm_id" {
  value = module.vm_tags.vm_id
}

output "applied_tags" {
  value = module.vm_tags.tags
}
```

### `modules/vm_tags/variables.tf`

```hcl
variable "vm_id" {
  type        = string
  description = "ID of the existing VM"
}

variable "tags" {
  type        = map(string)
  description = "Tags to add to the VM"
}
```

### `modules/vm_tags/main.tf`

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
    tags = var.tags
  }
}
```

### `modules/vm_tags/outputs.tf`

```hcl
output "vm_id" {
  value = azapi_update_resource.this.resource_id
}

output "tags" {
  value = var.tags
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

### Run

```bash
terraform init
terraform validate
terraform plan      # expect: Plan: 1 to add, 0 to change, 0 to destroy
terraform apply
```

Notes:

- The VM does not need to be stopped or restarted.
- The `main.tf` that contains `module "vm_tags"` is the one at the **root** of the folder, not the one inside `modules/`.
- `terraform destroy` does **not** remove the tag: this resource only sends a modification and cannot undo it.

## Final check (all methods)

```bash
az vm show -g "$RG" -n my-vm --query tags -o json

# Another reading, through the tags API
az tag list --resource-id "$(az vm show -g "$RG" -n my-vm --query id -o tsv)" -o json
```

Expected: `"Environment": "dev"` is present, and the tags you noted earlier are still there.

## Reset (to try another method)

```bash
az vm update -g "$RG" -n my-vm --remove tags.Environment
```

Also delete the local state of the previous attempt (`rm -f terraform.tfstate*`), otherwise Terraform believes the tag is already set.

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| The old tags disappeared | A command that replaces (`az resource tag` without `--is-incremental`, or `--operation replace`) | Use `--operation merge`, then re-add the lost tags |
| Tag not saved in the portal | **Apply** was not clicked | Go back to **Tags** and click **Apply** |
| `Environment=Dev` instead of `dev` | The value is case-sensitive | Correct the value to `dev` |
| Forbidden characters in the tag name | A name cannot contain `<`, `>`, `%`, `&`, `\`, `?`, `/` | Pick a name without these characters |
| More than 50 tags | Azure limit per resource | Remove unused tags |
| VM not found | Wrong resource group name, or the VM is in another region | Use the "group" column from the search above |
| `403 AuthorizationFailed ... register/action` on many providers | `azurerm` 4.x tries to register ~30 Resource Providers on the whole subscription | Add `resource_provider_registrations = "none"` to the provider block |
| Same error, or an authentication error, with an empty `providers.tf` | Without the provider block, the credentials are ignored | Fill in `providers.tf` |
| Terraform prompts for variables that are already in your tfvars | The file is not loaded automatically (wrong name such as `terraform.tfvars.txt`, wrong folder) | Name it exactly `terraform.tfvars`, next to `main.tf`, or pass `-var-file="file.tfvars"` |
| `Invalid client secret` | Secret empty, truncated, or the *Secret ID* copied instead of the *Value* | Recreate a secret and copy the **Value** |
| `Module not installed` | `terraform init` was not run | Run `terraform init` |
| `No declaration found for var.xxx`, or red underlines in VS Code | A root `variables.tf` is missing, or the editor has not reloaded | Check the files with `find`, run `terraform init` and `terraform validate`; if valid, run **Developer: Reload Window** |
| `azapi` error on the update | Operation refused or unexpected response shape | Print the error and use the CLI (`az tag update`) as a fallback |
| Old state or old credentials after a new session | The state file and credentials belong to a previous environment | Use a fresh folder and the credentials of the current session |

## Clean up

```bash
az vm update -g "$RG" -n my-vm --remove tags.Environment
```

`terraform destroy` does not remove the tag (see above).

## Security notes

- Never commit `terraform.tfvars` or state files: they contain a secret and resource details.
- Prefer short-lived secrets and the least privileged role (Contributor on one resource group, not on the subscription).
- Do not put secrets or personal data in tags: tags are visible in billing reports and to anyone who can read the resource.
- Run the three methods one after the other and undo the change in between, so each method starts from the same state.
