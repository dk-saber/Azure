output "public_ip_address" {
  value = data.azurerm_public_ip.pip.ip_address
}

output "nic_id" {
  value = local.nic_id
}
