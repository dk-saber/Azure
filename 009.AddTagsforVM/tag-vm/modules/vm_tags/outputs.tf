output "vm_id" {
  value = azapi_update_resource.this.resource_id
}

output "tags" {
  value = var.tags
}
