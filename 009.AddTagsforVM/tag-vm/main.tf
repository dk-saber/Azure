# VM existante : lue, pas gérée
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

module "vm_tags" {
  source = "./modules/vm_tags"

  vm_id = data.azurerm_virtual_machine.vm.id
  tags  = var.tags
}
