output "created_vnet_id" {
  value       = module.datacenter_vnet.vnet_id
  description = "The ID of the created Virtual Network exported from the module."
}