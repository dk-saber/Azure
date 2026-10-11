variable "vm_id" {
  type        = string
  description = "ID de la VM existante"
}

variable "primary_nic_id" {
  type        = string
  description = "NIC primaire déjà attachée"
}

variable "additional_nic_ids" {
  type        = list(string)
  description = "NIC supplémentaires à attacher"
}
