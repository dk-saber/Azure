data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

data "azurerm_managed_disk" "disk" {
  name                = var.disk_name
  resource_group_name = var.resource_group_name
}

module "datacenter_disk_attachment" {
  source = "./modules/disk_attachment"

  virtual_machine_id = data.azurerm_virtual_machine.vm.id
  managed_disk_id    = data.azurerm_managed_disk.disk.id
  lun                = 0
}