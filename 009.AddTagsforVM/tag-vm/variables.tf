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
  default = "nautilus-vm"
}

variable "tags" {
  type = map(string)
  default = {
    Environment = "dev"
  }
}
