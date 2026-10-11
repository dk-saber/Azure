# VM existante : lue, pas gérée
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

# Lecture des NIC déjà attachées à la VM, via l'API Azure
data "azapi_resource" "vm" {
  type                   = "Microsoft.Compute/virtualMachines@2024-03-01"
  resource_id            = data.azurerm_virtual_machine.vm.id
  response_export_values = ["properties.networkProfile.networkInterfaces"]
}

# NIC existante à attacher
data "azurerm_network_interface" "new" {
  name                = var.nic_name
  resource_group_name = var.resource_group_name
}

locals {
  # La première NIC de la liste est la NIC primaire
  primary_nic_id = data.azapi_resource.vm.output.properties.networkProfile.networkInterfaces[0].id
}

module "nic_attachment" {
  source = "./modules/vm_nic_attachment"

  vm_id              = data.azurerm_virtual_machine.vm.id
  primary_nic_id     = local.primary_nic_id
  additional_nic_ids = [data.azurerm_network_interface.new.id]
}
