variable "name" {
  type        = string
  description = "IP public name"
}

variable "resource_group_name" {
  type        = string
  description = "Exisitant Resource Group"
}

variable "location" {
  type        = string
  description = "Azure Region"
}

variable "allocation_method" {
  type    = string
  default = "Static"
}

variable "sku" {
  type    = string
  default = "Standard"
}