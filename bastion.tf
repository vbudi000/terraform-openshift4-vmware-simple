locals {
  bastion_ip = "${var.bastion_ip_address}"
}

resource "tls_private_key" "install_ssh_key" {
  algorithm   = "RSA"
  rsa_bits = "2048"
}

resource "vsphere_virtual_machine" "bastion" {
  count = "${var.datastore != "" ? 1 : 0}"
  folder     = "${var.folder}"

  #####
  # VM Specifications
  ####
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"

  name      = "${lower(var.name)}-bastion"
  num_cpus  = "${var.install["vcpu"]}"
  memory    = "${var.install["memory"]}"

  ####
  # Disk specifications
  ####
  datastore_id  = "${data.vsphere_datastore.datastore.0.id}"
  guest_id      = "${data.vsphere_virtual_machine.rhel_template.guest_id}"
  scsi_type     = "${data.vsphere_virtual_machine.rhel_template.scsi_type}"

  disk {
      label            = "${lower(var.name)}-bastion.vmdk"
      size             = "${var.install["disk_size"]        != "" ? var.install["disk_size"]        : data.vsphere_virtual_machine.rhel_template.disks.0.size}"
      eagerly_scrub    = "${var.install["eagerly_scrub"]    != "" ? var.install["eagerly_scrub"]    : data.vsphere_virtual_machine.rhel_template.disks.0.eagerly_scrub}"
      thin_provisioned = "${var.install["thin_provisioned"] != "" ? var.install["thin_provisioned"] : data.vsphere_virtual_machine.rhel_template.disks.0.thin_provisioned}"
      keep_on_remove   = false
      unit_number      = 0
  }

  ####
  # Network specifications
  ####
  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.rhel_template.network_interface_types[0]}"
  }

  ####
  # VM Customizations
  ####
  clone {
    template_uuid = "${data.vsphere_virtual_machine.rhel_template.id}"

    customize {
      linux_options {
        host_name = "${lower(var.name)}-bastion"
        domain    = "${var.domain != "" ? var.domain : format("%s.local", var.name)}"
      }

      network_interface {
        ipv4_address = "${var.bastion_ip_address}"
        ipv4_netmask = "${var.netmask}"
      }

      ipv4_gateway    = "${var.gateway}"

      dns_server_list = concat(var.dns_servers,var.upstream_dns_servers)
      dns_suffix_list = list(format("%v.%v", var.name, var.domain), var.domain)
    }
  }
}

resource "vsphere_virtual_machine" "bastion_ds_cluster" {
  count = "${var.datastore_cluster != "" ? 1 : 0}"


  folder     = "${var.folder}"

  #####
  # VM Specifications
  ####
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"

  name      = "${lower(var.name)}-bastion"
  num_cpus  = "${var.install["vcpu"]}"
  memory    = "${var.install["memory"]}"

  ####
  # Disk specifications
  ####
  datastore_cluster_id  = "${data.vsphere_datastore_cluster.datastore_cluster.0.id}"
  guest_id      = "${data.vsphere_virtual_machine.rhel_template.guest_id}"
  scsi_type     = "${data.vsphere_virtual_machine.rhel_template.scsi_type}"

  disk {
      label            = "${lower(var.name)}-bastion.vmdk"
      size             = "${var.install["disk_size"]        != "" ? var.install["disk_size"]        : data.vsphere_virtual_machine.rhel_template.disks.0.size}"
      eagerly_scrub    = "${var.install["eagerly_scrub"]    != "" ? var.install["eagerly_scrub"]    : data.vsphere_virtual_machine.rhel_template.disks.0.eagerly_scrub}"
      thin_provisioned = "${var.install["thin_provisioned"] != "" ? var.install["thin_provisioned"] : data.vsphere_virtual_machine.rhel_template.disks.0.thin_provisioned}"
      keep_on_remove   = false
      unit_number      = 0
  }

  ####
  # Network specifications
  ####
  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.rhel_template.network_interface_types[0]}"
  }

  ####
  # VM Customizations
  ####
  clone {
    template_uuid = "${data.vsphere_virtual_machine.rhel_template.id}"

    customize {
      linux_options {
        host_name = "${lower(var.name)}-bastion"
        domain    = "${var.domain != "" ? var.domain : format("%s.local", var.name)}"
      }

      network_interface {
        ipv4_address = "${var.bastion_ip_address}"
        ipv4_netmask = "${var.netmask}"
      }

      ipv4_gateway    = "${var.gateway}"

      dns_server_list = concat(var.dns_servers,var.upstream_dns_servers)
      dns_suffix_list = list(format("%v.%v", var.name, var.domain), var.domain)
    }
  }
}

# because certificate generation is time sensitive, make sure that system clock is set to UTC to 
# match all of the RHCOS VMs
resource "null_resource" "set_systemclock_utc" {
  depends_on = [
    "vsphere_virtual_machine.bastion",
    "vsphere_virtual_machine.bastion_ds_cluster"
  ]

  connection {
    type        = "ssh"
    host        = "${local.bastion_ip}"
    user        = "${var.ssh_user}"
    password    = "${var.ssh_password}"
    private_key = "${file(var.ssh_private_key_file)}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo timedatectl set-timezone UTC"
    ]
  }
}

resource "null_resource" "install_httpd" {
  depends_on = [
    "null_resource.rhn_register"
  ]

  connection {
    type        = "ssh"
    host        = "${local.bastion_ip}"
    user        = "${var.ssh_user}"
    password    = "${var.ssh_password}"
    private_key = "${file(var.ssh_private_key_file)}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install -y httpd",
      "sed -i 's/Listen 80/Listen 1080/' /etc/httpd/conf/httpd.conf",
      "semanage port -a -t http_port_t -p tcp 1080",
      "sudo systemctl enable httpd",
      "sudo systemctl start httpd"
    ]
  }
}

resource "null_resource" "open_ports_firewalld" {
  depends_on = [
    "null_resource.set_systemclock_utc"
  ]
 
  connection {
    type          = "ssh"
    host          = "${local.bastion_ip}"
    user          = "${var.ssh_user}"
    password      = "${var.ssh_password}"
    private_key   = "${file(var.ssh_private_key_file)}"
  }

  provisioner "remote-exec" {
    when = "create"
    inline = [
      "sudo firewall-cmd --zone=public --add-port=1080/tcp",
      "sudo firewall-cmd --zone=public --add-port=1080/tcp --permanent"
    ]
  }
}

resource "null_resource" "write_ssh_key" {
  depends_on = [
    "null_resource.set_systemclock_utc"
  ]
 
  connection {
    type        = "ssh"
    host        = "${local.bastion_ip}"
    user        = "${var.ssh_user}"
    password    = "${var.ssh_password}"
    private_key = "${file(var.ssh_private_key_file)}"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~${var.ssh_user}/.ssh",
      "echo '${tls_private_key.install_ssh_key.public_key_openssh}' > ~${var.ssh_user}/.ssh/id_rsa.pub",
      "echo '${tls_private_key.install_ssh_key.private_key_pem}' > ~${var.ssh_user}/.ssh/id_rsa",
      "chmod 700 ~${var.ssh_user}/.ssh",
      "chmod 600 ~${var.ssh_user}/.ssh/id_rsa.pub",
      "chmod 600 ~${var.ssh_user}/.ssh/id_rsa"
    ]
  }
}

