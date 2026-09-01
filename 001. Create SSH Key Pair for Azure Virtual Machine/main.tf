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
