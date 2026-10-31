terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

resource "azapi_update_resource" "this" {
  type        = "Microsoft.Compute/virtualMachines@2024-03-01"
  resource_id = var.vm_id

  body = {
    tags = var.tags
  }
}
