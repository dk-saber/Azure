variable "virtual_machine_id" {
  type        = string
  description = "ID de la VM cible"
}

variable "managed_disk_id" {
  type        = string
  description = "ID du disque managé existant"
}

variable "lun" {
  type        = number
  default     = 0
  description = "Numéro d'unité logique, unique par VM"
}

variable "caching" {
  type    = string
  default = "ReadWrite"
}

variable "create_option" {
  type        = string
  default     = "Attach"
  description = "Attach = relier un disque existant"
}