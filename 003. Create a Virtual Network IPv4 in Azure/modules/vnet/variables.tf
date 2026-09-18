variable "vnet_name" {
  type        = string
  description = "The name of the Virtual Network."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the existing target Resource Group."
}

variable "location" {
  type        = string
  description = "The Azure region where the Virtual Network will be created."
}

variable "address_space" {
  type        = list(string)
  description = "The address space CIDR blocks allocated to the Virtual Network."
}