terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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

# Groupe de ressources existant
data "azurerm_resource_group" "lab_rg" {
  name = "kml_rg_main-5432f42caca34f21"
}

# Appel du module
module "datacenter_vnet" {
  source              = "./modules/vnet"
  vnet_name           = "datacenter-vnet-01"
  location            = "westus"
  resource_group_name = data.azurerm_resource_group.lab_rg.name
  address_space       = ["192.168.1.0/24"]
}