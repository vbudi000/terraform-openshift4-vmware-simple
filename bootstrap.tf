###################################
##### Create the VMs
###################################
resource "vsphere_virtual_machine" "bootstrap" {
  count = "${var.datastore != "" ? (var.bootstrap_complete ? 0 : 1) : 0}"
  depends_on = [
    "null_resource.generate_ignition_config"
  ]

  folder     = "${local.folder}"

  #####
  # VM Specifications
  ####
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"

  name      = "${lower(var.name)}-bootstrap"
  num_cpus  = "${var.bootstrap["vcpu"]}"
  memory    = "${var.bootstrap["memory"]}"

  #scsi_controller_count = 1
  #scsi_type = "lsilogic-sas"

  ####
  # Disk specifications
  ####
  datastore_id  = "${data.vsphere_datastore.datastore.0.id}"
  guest_id      = "${data.vsphere_virtual_machine.rhcos_template.guest_id}"
  scsi_type     = "${data.vsphere_virtual_machine.rhcos_template.scsi_type}"

  disk {
      label            = "${lower(var.name)}-bootstrap-boot.vmdk"
      size             = "${var.boot_disk["disk_size"]        != "" ? var.boot_disk["disk_size"]        : data.vsphere_virtual_machine.rhcos_template.disks.0.size}"
      eagerly_scrub    = "${var.boot_disk["eagerly_scrub"]    != "" ? var.boot_disk["eagerly_scrub"]    : data.vsphere_virtual_machine.rhcos_template.disks.0.eagerly_scrub}"
      thin_provisioned = "${var.boot_disk["thin_provisioned"] != "" ? var.boot_disk["thin_provisioned"] : data.vsphere_virtual_machine.rhcos_template.disks.0.thin_provisioned}"
      keep_on_remove   = false
      unit_number      = 0
  }
  disk {
      label            = "${lower(var.name)}-bootstrap-disk1.vmdk"
      size             = "${var.additional_disk["disk_size"]}"
      eagerly_scrub    = "${var.additional_disk["eagerly_scrub"]    != "" ? var.additional_disk["eagerly_scrub"]    : data.vsphere_virtual_machine.rhcos_template.disks.0.eagerly_scrub}"
      thin_provisioned = "${var.additional_disk["thin_provisioned"] != "" ? var.additional_disk["thin_provisioned"] : data.vsphere_virtual_machine.rhcos_template.disks.0.thin_provisioned}"
      keep_on_remove   = false
      unit_number      = 1
  }

  ####
  # Network specifications
  ####
  network_interface {
    network_id   = "${data.vsphere_network.private_network.id}"
    adapter_type = "${data.vsphere_virtual_machine.rhcos_template.network_interface_types[0]}"
  }

  ####
  # VM Customizations
  ####
  clone {
    template_uuid = "${data.vsphere_virtual_machine.rhcos_template.id}"
  }

  extra_config = {
    # TODO: this requires CPU reservation
    # "sched.cpu.latencySensitivity" = "high"
    "sched.cpu.latencySensitivity" = "normal"
  }

  vapp {
    properties = {
      "guestinfo.ignition.config.data" = "${base64encode(data.ignition_config.bootstrap_ign.rendered)}"
      "guestinfo.ignition.config.data.encoding" = "base64"
    }
  }
}


resource "vsphere_virtual_machine" "bootstrap_ds_cluster" {
  count = "${var.datastore_cluster != "" ? (var.bootstrap_complete ? 0 : 1) : 0}"
  depends_on = [
    "null_resource.generate_ignition_config"
  ]

  folder     = "${local.folder}"

  #####
  # VM Specifications
  ####
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"

  name      = "${lower(var.name)}-bootstrap"
  num_cpus  = "${var.bootstrap["vcpu"]}"
  memory    = "${var.bootstrap["memory"]}"

  #scsi_controller_count = 1
  #scsi_type = "lsilogic-sas"

  ####
  # Disk specifications
  ####
  datastore_cluster_id  = "${data.vsphere_datastore_cluster.datastore_cluster.0.id}"
  guest_id      = "${data.vsphere_virtual_machine.rhcos_template.guest_id}"
  scsi_type     = "${data.vsphere_virtual_machine.rhcos_template.scsi_type}"

  disk {
      label            = "${lower(var.name)}-bootstrap-boot.vmdk"
      size             = "${var.boot_disk["disk_size"]        != "" ? var.boot_disk["disk_size"]        : data.vsphere_virtual_machine.rhcos_template.disks.0.size}"
      eagerly_scrub    = "${var.boot_disk["eagerly_scrub"]    != "" ? var.boot_disk["eagerly_scrub"]    : data.vsphere_virtual_machine.rhcos_template.disks.0.eagerly_scrub}"
      thin_provisioned = "${var.boot_disk["thin_provisioned"] != "" ? var.boot_disk["thin_provisioned"] : data.vsphere_virtual_machine.rhcos_template.disks.0.thin_provisioned}"
      keep_on_remove   = false
      unit_number      = 0
  }
  disk {
      label            = "${lower(var.name)}-bootstrap-disk1.vmdk"
      size             = "${var.additional_disk["disk_size"]}"
      eagerly_scrub    = "${var.additional_disk["eagerly_scrub"]    != "" ? var.additional_disk["eagerly_scrub"]    : data.vsphere_virtual_machine.rhcos_template.disks.0.eagerly_scrub}"
      thin_provisioned = "${var.additional_disk["thin_provisioned"] != "" ? var.additional_disk["thin_provisioned"] : data.vsphere_virtual_machine.rhcos_template.disks.0.thin_provisioned}"
      keep_on_remove   = false
      unit_number      = 1
  }

  ####
  # Network specifications
  ####
  network_interface {
    network_id   = "${data.vsphere_network.private_network.id}"
    adapter_type = "${data.vsphere_virtual_machine.rhcos_template.network_interface_types[0]}"
  }

  ####
  # VM Customizations
  ####
  clone {
    template_uuid = "${data.vsphere_virtual_machine.rhcos_template.id}"
  }

  extra_config = {
    # TODO: this requires CPU reservation
    # "sched.cpu.latencySensitivity" = "high"
    "sched.cpu.latencySensitivity" = "normal"
  }

  vapp {
    properties = {
      "guestinfo.ignition.config.data" = "${base64encode(data.ignition_config.bootstrap_ign.rendered)}"
      "guestinfo.ignition.config.data.encoding" = "base64"
    }
  }
}
