terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

locals {
  ipc   = var.ip_configuration
  props = local.ipc.properties

  # privateIPAddress n'est repris que si l'allocation est Static
  static_private_ip = {
    for k, v in { privateIPAddress = try(local.props.privateIPAddress, "") } :
    k => v if local.props.privateIPAllocationMethod == "Static"
  }
}

resource "azapi_update_resource" "this" {
  type        = "Microsoft.Network/networkInterfaces@2024-01-01"
  resource_id = var.nic_id

  body = {
    properties = {
      ipConfigurations = [
        {
          name = local.ipc.name
          properties = merge(
            {
              subnet                    = { id = local.props.subnet.id }
              privateIPAllocationMethod = local.props.privateIPAllocationMethod
              primary                   = try(local.props.primary, true)
              publicIPAddress           = { id = var.public_ip_id }
            },
            local.static_private_ip
          )
        }
      ]
    }
  }
}
