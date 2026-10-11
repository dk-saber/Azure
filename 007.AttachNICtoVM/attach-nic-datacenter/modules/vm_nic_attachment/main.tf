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
    properties = {
      networkProfile = {
        networkInterfaces = concat(
          [{ id = var.primary_nic_id, properties = { primary = true } }],
          [for id in var.additional_nic_ids : { id = id, properties = { primary = false } }]
        )
      }
    }
  }
}
