# VM existante : lue, pas gérée
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

# IP publique existante à associer
data "azurerm_public_ip" "pip" {
  name                = var.public_ip_name
  resource_group_name = var.resource_group_name
}

# NIC de la VM, lues via l'API Azure
data "azapi_resource" "vm" {
  type                   = "Microsoft.Compute/virtualMachines@2024-03-01"
  resource_id            = data.azurerm_virtual_machine.vm.id
  response_export_values = ["properties.networkProfile.networkInterfaces"]
}

locals {
  # La première NIC de la VM est la NIC primaire
  nic_id = data.azapi_resource.vm.output.properties.networkProfile.networkInterfaces[0].id
}

# Configuration IP actuelle de cette NIC
data "azapi_resource" "nic" {
  type                   = "Microsoft.Network/networkInterfaces@2024-01-01"
  resource_id            = local.nic_id
  response_export_values = ["properties.ipConfigurations"]
}

module "nic_public_ip" {
  source = "./modules/nic_public_ip"

  nic_id           = local.nic_id
  ip_configuration = data.azapi_resource.nic.output.properties.ipConfigurations[0]
  public_ip_id     = data.azurerm_public_ip.pip.id
}
