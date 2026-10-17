variable "nic_id" {
  type        = string
  description = "ID de la NIC existante"
}

variable "ip_configuration" {
  type        = any
  description = "Configuration IP actuelle de la NIC (lue via l'API Azure)"
}

variable "public_ip_id" {
  type        = string
  description = "ID de l'IP publique à associer"
}
