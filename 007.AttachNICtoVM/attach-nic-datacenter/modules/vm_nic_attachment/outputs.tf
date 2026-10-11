output "nic_ids" {
  value = concat([var.primary_nic_id], var.additional_nic_ids)
}
