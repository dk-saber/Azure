resource "azurerm_virtual_machine_data_disk_attachment" "this" {
  virtual_machine_id = var.virtual_machine_id
  managed_disk_id    = var.managed_disk_id
  lun                = var.lun
  caching            = var.caching
  create_option      = var.create_option
}