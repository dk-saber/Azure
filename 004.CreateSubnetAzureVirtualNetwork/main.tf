terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}

module "devops_vnet" {
  source = "./modules/vnet"

  vnet_name                = var.vnet_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  address_space            = var.address_space
  subnet_name              = var.subnet_name
  subnet_address_prefixes  = var.subnet_address_prefixes
}