variable "vm_id" {
  type        = string
  description = "ID de la VM existante"
}

variable "tags" {
  type        = map(string)
  description = "Tags à ajouter à la VM"
}
