# Terraform Lab: Create an IPv4 Virtual Network in Azure

## Overview

This lab demonstrates how to use **Terraform** and the **AzureRM provider** to create an Azure Virtual Network (VNet) with an IPv4 address space.

The configuration also demonstrates how to:

- Use an existing Azure Resource Group with a Terraform data source.
- Create a reusable Terraform module for the Virtual Network.
- Define variables and outputs.
- Use Terraform provider configuration for Azure authentication.
- Deploy infrastructure using `terraform init`, `terraform plan`, and `terraform apply`.

## Architecture

```text
Azure Subscription
│
└── Existing Resource Group
    │
    └── Virtual Network
        └── Address Space: 192.168.1.0/24
```

### Virtual Network Configuration

| Property | Value |
|---|---|
| Resource type | Azure Virtual Network |
| VNet name | `datacenter-vnet-01` |
| Address space | `192.168.1.0/24` |
| Azure region | `West US` |
| Resource Group | Existing Resource Group |
| Terraform provider | `hashicorp/azurerm` |
| Provider version | `~> 3.0` |

## Project Structure

```text
.
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
├── .terraform.lock.hcl
└── modules/
    └── vnet/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Why Use Terraform Modules?

Terraform modules are an important part of building maintainable and scalable Infrastructure as Code.

Instead of defining every resource directly in the root Terraform configuration, related resources can be grouped into reusable modules.

In this lab, the Virtual Network is implemented as a dedicated `vnet` module:

```text
modules/
└── vnet/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

### 1. Reusability

A module can be reused several times with different parameters.

For example, the same VNet module could be used to create different networks:

```hcl
module "production_vnet" {
  source              = "./modules/vnet"
  vnet_name           = "production-vnet"
  location            = "westus"
  resource_group_name = data.azurerm_resource_group.lab_rg.name
  address_space       = ["10.10.0.0/16"]
}

module "development_vnet" {
  source              = "./modules/vnet"
  vnet_name           = "development-vnet"
  location            = "westus"
  resource_group_name = data.azurerm_resource_group.lab_rg.name
  address_space       = ["10.20.0.0/16"]
}
```

The resource definition does not need to be duplicated.

### 2. Maintainability

Modules separate infrastructure into logical components.

For example, a larger Azure project could contain:

```text
modules/
├── vnet/
├── subnet/
├── vm/
├── storage/
├── aks/
└── monitoring/
```

Each module can have its own resources, variables, and outputs.

This makes the Terraform code easier to understand and maintain.

### 3. Standardization

Modules allow an organization to define a standard way of creating infrastructure.

For example, a company can create a networking module that always includes:

- A standardized naming convention.
- Approved address spaces.
- Required tags.
- Network security configuration.
- Specific Azure regions.
- Organization-wide settings.

Teams can then reuse the same module instead of implementing their own versions.

### 4. Separation of Responsibilities

Modules help separate infrastructure components and their responsibilities.

For example:

```text
Root Module
│
├── Network Module
│   └── Virtual Network
│
├── Compute Module
│   └── Virtual Machines
│
└── Storage Module
    └── Storage Accounts
```

The root module defines how the different components are combined, while each child module manages its own infrastructure.

### 5. Easier Scaling

As infrastructure grows, managing everything in a single `main.tf` file becomes difficult.

Modules allow the project to scale while keeping the code organized.

For example:

```text
Infrastructure
│
├── Networking
│   ├── VNet
│   ├── Subnets
│   └── NSGs
│
├── Compute
│   ├── VMs
│   └── VM Scale Sets
│
├── Kubernetes
│   └── AKS
│
├── Storage
│   └── Storage Accounts
│
└── Monitoring
    ├── Log Analytics
    └── Monitoring
```

Each component can be implemented as a separate Terraform module.

### 6. Input and Output Interfaces

A module can expose a simple interface using variables and outputs.

For example, the VNet module receives:

```hcl
variable "vnet_name" {}
variable "location" {}
variable "resource_group_name" {}
variable "address_space" {}
```

It can then expose information such as the VNet ID:

```hcl
output "vnet_id" {
  value = azurerm_virtual_network.vnet.id
}
```

The root module can consume this output:

```hcl
module.datacenter_vnet.vnet_id
```

This creates a clear separation between the implementation of the module and the configuration that uses it.

### Module Design Principle

A good Terraform module should generally be:

- Reusable
- Configurable
- Well documented
- Focused on a specific infrastructure component
- Independent from unnecessary implementation details
- Designed with clear inputs and outputs

For larger projects, modules can also be stored in a dedicated Git repository or published to the Terraform Registry for reuse across multiple projects.

## Root Module

The root module:

1. Configures Terraform and the AzureRM provider.
2. Reads the existing Resource Group using `azurerm_resource_group`.
3. Calls the `vnet` module.
4. Exposes the ID of the created VNet as an output.

Example:

```hcl
data "azurerm_resource_group" "lab_rg" {
  name = "YOUR_RESOURCE_GROUP_NAME"
}

module "datacenter_vnet" {
  source              = "./modules/vnet"
  vnet_name           = "datacenter-vnet-01"
  location            = "westus"
  resource_group_name = data.azurerm_resource_group.lab_rg.name
  address_space       = ["192.168.1.0/24"]
}
```

## VNet Module

The module contains the actual Azure Virtual Network resource:

```hcl
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
}
```

This makes the VNet configuration reusable for other projects.

## Prerequisites

Before starting, make sure you have:

- An Azure subscription.
- An existing Azure Resource Group.
- Terraform installed.
- An Azure authentication method configured.
- Internet access to download the AzureRM provider.

Check the Terraform installation:

```bash
terraform version
```

## Azure Authentication

This project uses the AzureRM provider.

The recommended approach for local development is to avoid storing credentials directly in Terraform files.

For example, with Azure CLI authentication:

```bash
az login
```

Then configure the provider:

```hcl
provider "azurerm" {
  features {}
  skip_provider_registration = true
}
```

For a Service Principal, environment variables can also be used:

```bash
export ARM_CLIENT_ID="..."
export ARM_CLIENT_SECRET="..."
export ARM_TENANT_ID="..."
export ARM_SUBSCRIPTION_ID="..."
```

On Windows PowerShell:

```powershell
$env:ARM_CLIENT_ID="..."
$env:ARM_CLIENT_SECRET="..."
$env:ARM_TENANT_ID="..."
$env:ARM_SUBSCRIPTION_ID="..."
```

> Never commit Azure passwords, client secrets, or other credentials to GitHub.

## Terraform Workflow

### 1. Initialize the project

```bash
terraform init
```

This initializes the working directory and downloads the required AzureRM provider.

### 2. Format the Terraform files

```bash
terraform fmt -recursive
```

### 3. Validate the configuration

```bash
terraform validate
```

### 4. Review the execution plan

```bash
terraform plan
```

Review the resources Terraform intends to create before applying the configuration.

### 5. Create the Virtual Network

```bash
terraform apply
```

Confirm the operation when Terraform asks for approval.

You can also use:

```bash
terraform apply -auto-approve
```

Use `-auto-approve` carefully, especially outside a lab environment.

## Verify the Deployment

After the deployment, Terraform displays the VNet ID:

```text
created_vnet_id = /subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/datacenter-vnet-01
```

You can also verify the resource in the Azure Portal:

```text
Azure Portal
  → Resource Groups
  → YOUR_RESOURCE_GROUP
  → datacenter-vnet-01
```

## Useful Terraform Commands

| Command | Description |
|---|---|
| `terraform init` | Initialize the Terraform project |
| `terraform fmt -recursive` | Format Terraform files |
| `terraform validate` | Validate the configuration |
| `terraform plan` | Preview infrastructure changes |
| `terraform apply` | Create or update infrastructure |
| `terraform output` | Display Terraform outputs |
| `terraform show` | Display the current state |
| `terraform destroy` | Delete resources managed by Terraform |

## Outputs

The root module exposes the Virtual Network ID:

```hcl
output "created_vnet_id" {
  value       = module.datacenter_vnet.vnet_id
  description = "The ID of the created Virtual Network exported from the module."
}
```

The module also provides:

```hcl
output "vnet_id" {
  value = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  value = azurerm_virtual_network.vnet.name
}
```

## Important Notes

### Existing Resource Group

The Resource Group is not created by this Terraform configuration.

It is retrieved using:

```hcl
data "azurerm_resource_group" "lab_rg" {
  name = "YOUR_RESOURCE_GROUP_NAME"
}
```

Therefore, the Resource Group must already exist before running `terraform apply`.

### State Files

Terraform creates local state files such as:

```text
terraform.tfstate
terraform.tfstate.backup
```

These files can contain sensitive infrastructure information and should normally not be committed to Git.

Add the following to `.gitignore`:

```gitignore
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
```

Keep `.terraform.lock.hcl` in Git because it locks the provider dependency versions and checksums.

## Troubleshooting

### Provider initialization problem

```bash
terraform init -upgrade
```

### Authentication error

Verify your Azure authentication:

```bash
az account show
```

For Service Principal authentication, verify:

```text
ARM_CLIENT_ID
ARM_CLIENT_SECRET
ARM_TENANT_ID
ARM_SUBSCRIPTION_ID
```

### Resource Group not found

Make sure the Resource Group specified in:

```hcl
data "azurerm_resource_group" "lab_rg"
```

exists in the Azure subscription being used.

## Learning Objectives

After completing this lab, you should understand how to:

- Configure Terraform for Azure.
- Use the `azurerm` provider.
- Read an existing Azure resource with a data source.
- Create an Azure Virtual Network.
- Define an IPv4 CIDR address space.
- Build and use a reusable Terraform module.
- Understand why modules are important in Infrastructure as Code.
- Pass variables from the root module to a child module.
- Export resource information using outputs.
- Follow a basic Terraform infrastructure-as-code workflow.

## Cleanup

To remove the Virtual Network created by Terraform:

```bash
terraform destroy
```

Review the resources Terraform plans to delete and confirm the operation.

> `terraform destroy` deletes resources managed by the current Terraform configuration. Use it carefully and never run it against a shared or production environment without checking the plan.

## License

This project is provided for educational and laboratory purposes.