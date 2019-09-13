
##################################
#### Create the VMs
##################################
resource "vsphere_virtual_machine" "worker" {
  depends_on = [
    "null_resource.haproxy_cfg",
    "null_resource.generate_ignition_config"
  ]

  folder     = "${local.folder}"

  #####
  # VM Specifications
  ####
  count            = "${var.datastore != "" ? var.worker["count"] : 0}"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"

  name      = "${element(data.template_file.worker_hostname.*.rendered, count.index)}"
  num_cpus  = "${var.worker["vcpu"]}"
  memory    = "${var.worker["memory"]}"

  #scsi_controller_count = 1
  #scsi_type = "lsilogic-sas"

  ####
  # Disk specifications
  ####
  datastore_id  = "${data.vsphere_datastore.datastore.0.id}"
  guest_id      = "${data.vsphere_virtual_machine.rhcos_template.guest_id}"
  scsi_type     = "${data.vsphere_virtual_machine.rhcos_template.scsi_type}"

  disk {
      label            = "${format("${lower(var.name)}-worker%02d-boot.vmdk", count.index + 1) }"
      size             = "${var.boot_disk["disk_size"]        != "" ? var.boot_disk["disk_size"]        : data.vsphere_virtual_machine.rhcos_template.disks.0.size}"
      eagerly_scrub    = "${var.boot_disk["eagerly_scrub"]    != "" ? var.boot_disk["eagerly_scrub"]    : data.vsphere_virtual_machine.rhcos_template.disks.0.eagerly_scrub}"
      thin_provisioned = "${var.boot_disk["thin_provisioned"] != "" ? var.boot_disk["thin_provisioned"] : data.vsphere_virtual_machine.rhcos_template.disks.0.thin_provisioned}"
      keep_on_remove   = false
      unit_number      = 0
  }
  
  disk {
      label            = "${format("${lower(var.name)}-worker%02d_disk1.vmdk", count.index + 1) }"
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

  # TODO: in openshift 4, the bootstrap node generates a certificate for the api endpoint 10 minutes in the future, which means
  # the node will fail getting its config from the machine config server for 10 minutes until the certificate
  # becomes valid, delaying its boot and setup of static IP address.  disable the wait for an IP address to show up.  
  # because the installer synchronously waits for bootstrap to finish, we should catch any errors there.
  # going to have to ask red hat about this ...
  wait_for_guest_net_timeout = 0

  ####
  # VM Customizations
  ####
  clone {
    template_uuid = "${data.vsphere_virtual_machine.rhcos_template.id}"
  }

  vapp {
    properties = {
      "guestinfo.ignition.config.data" = "${base64encode(element(data.ignition_config.worker_ign.*.rendered, count.index))}"
      "guestinfo.ignition.config.data.encoding" = "base64"
    }
  }
}

resource "vsphere_virtual_machine" "worker_ds_cluster" {
  depends_on = [
    "null_resource.haproxy_cfg",
    "null_resource.generate_ignition_config"
  ]

  folder     = "${local.folder}"

  #####
  # VM Specifications
  ####
  count            = "${var.datastore_cluster != "" ? var.worker["count"] : 0}"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"

  name      = "${element(data.template_file.worker_hostname.*.rendered, count.index)}"
  num_cpus  = "${var.worker["vcpu"]}"
  memory    = "${var.worker["memory"]}"

  #scsi_controller_count = 1
  #scsi_type = "lsilogic-sas"

  ####
  # Disk specifications
  ####
  datastore_cluster_id  = "${data.vsphere_datastore_cluster.datastore_cluster.0.id}"
  guest_id      = "${data.vsphere_virtual_machine.rhcos_template.guest_id}"
  scsi_type     = "${data.vsphere_virtual_machine.rhcos_template.scsi_type}"

  disk {
      label            = "${format("${lower(var.name)}-worker%02d-boot.vmdk", count.index + 1) }"
      size             = "${var.boot_disk["disk_size"]        != "" ? var.boot_disk["disk_size"]        : data.vsphere_virtual_machine.rhcos_template.disks.0.size}"
      eagerly_scrub    = "${var.boot_disk["eagerly_scrub"]    != "" ? var.boot_disk["eagerly_scrub"]    : data.vsphere_virtual_machine.rhcos_template.disks.0.eagerly_scrub}"
      thin_provisioned = "${var.boot_disk["thin_provisioned"] != "" ? var.boot_disk["thin_provisioned"] : data.vsphere_virtual_machine.rhcos_template.disks.0.thin_provisioned}"
      keep_on_remove   = false
      unit_number      = 0
  }
  
  disk {
      label            = "${format("${lower(var.name)}-worker%02d_disk1.vmdk", count.index + 1) }"
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

  # TODO: in openshift 4, the bootstrap node generates a certificate for the api endpoint 10 minutes in the future, which means
  # the node will fail getting its config from the machine config server for 10 minutes until the certificate
  # becomes valid, delaying its boot and setup of static IP address.  disable the wait for an IP address to show up.  
  # because the installer synchronously waits for bootstrap to finish, we should catch any errors there.
  # going to have to ask red hat about this ...
  wait_for_guest_net_timeout = 0

  ####
  # VM Customizations
  ####
  clone {
    template_uuid = "${data.vsphere_virtual_machine.rhcos_template.id}"
  }

  vapp {
    properties = {
      "guestinfo.ignition.config.data" = "${base64encode(element(data.ignition_config.worker_ign.*.rendered, count.index))}"
      "guestinfo.ignition.config.data.encoding" = "base64"
    }
  }
}
