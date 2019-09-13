locals {
  bastion_ip = "${element(compact(list(var.bastion_public_ip_address, var.bastion_private_ip_address)), 0)}"
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
  dynamic "network_interface" {
    for_each = compact(concat(data.vsphere_network.public_network.*.id, list(data.vsphere_network.private_network.id)))
    content {
      network_id   = "${network_interface.value}"
      adapter_type = "${data.vsphere_virtual_machine.rhel_template.network_interface_types[0]}"
    }
  }

  ####
  # VM Customizations
  ####
  clone {
    template_uuid = "${data.vsphere_virtual_machine.rhel_template.id}"

    customize {
      linux_options {
        host_name = "${lower(var.name)}-bastion"
        domain    = "${var.private_domain != "" ? var.private_domain : format("%s.local", var.name)}"
      }

      dynamic "network_interface" {
        for_each = compact(concat(data.vsphere_network.public_network.*.id, list(data.vsphere_network.private_network.id)))
        content {
          ipv4_address = "${element(compact(list(var.bastion_public_ip_address, var.bastion_private_ip_address)), network_interface.key)}"
          ipv4_netmask = 16
        }
      }

      ipv4_gateway    = "${var.public_gateway != "" ? var.public_gateway : var.private_gateway}"

      dns_server_list = "${var.private_dns_servers}"
      dns_suffix_list = list(format("%v.%v", var.name, var.private_domain), var.private_domain)
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
  dynamic "network_interface" {
    for_each = compact(concat(data.vsphere_network.public_network.*.id, list(data.vsphere_network.private_network.id)))
    content {
      network_id   = "${network_interface.value}"
      adapter_type = "${data.vsphere_virtual_machine.rhel_template.network_interface_types[0]}"
    }
  }

  ####
  # VM Customizations
  ####
  clone {
    template_uuid = "${data.vsphere_virtual_machine.rhel_template.id}"

    customize {
      linux_options {
        host_name = "${lower(var.name)}-bastion"
        domain    = "${var.private_domain != "" ? var.private_domain : format("%s.local", var.name)}"
      }

      dynamic "network_interface" {
        for_each = compact(concat(data.vsphere_network.public_network.*.id, list(data.vsphere_network.private_network.id)))
        content {
          ipv4_address = "${element(compact(list(var.bastion_private_ip_address)), network_interface.key)}"
          ipv4_netmask = 16
        }
      }

      ipv4_gateway    = "${var.public_gateway != "" ? var.public_gateway : var.private_gateway}"

      dns_server_list = "${var.private_dns_servers}"
      dns_suffix_list = list(format("%v.%v", var.name, var.private_domain), var.private_domain)
    }
  }
}

resource "null_resource" "openshift_installer" {
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
      "set -e",
      "wget -r -l1 -np -nd https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/ -P /tmp -A 'openshift-install-linux-4*.tar.gz'",
      "tar zxvf /tmp/openshift-install-linux-4*.tar.gz -C /tmp",
    ]
  }
}

resource "null_resource" "openshift_client" {
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
      "set -e",
      "wget -r -l1 -np -nd https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/ -P /tmp -A 'openshift-client-linux-4*.tar.gz'",
      "sudo tar zxvf /tmp/openshift-client-linux-4*.tar.gz -C /usr/local/bin",
    ]
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
    "vsphere_virtual_machine.bastion",
    "vsphere_virtual_machine.bastion_ds_cluster",
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
      "sudo subscription-manager repos --enable='rhel-7-server-rpms'",
      "sudo yum install -y httpd",
      "sudo systemctl enable httpd",
      "sudo systemctl start httpd"
    ]
  }
}

resource "null_resource" "open_ports_firewalld" {
  depends_on = [
    "vsphere_virtual_machine.bastion",
    "vsphere_virtual_machine.bastion_ds_cluster"
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
      "sudo firewall-cmd --zone=public --add-port=80/tcp",
      "sudo firewall-cmd --zone=public --add-port=80/tcp --permanent"
    ]
  }
}

data "template_file" "install_config_yaml" {
  template = <<EOF
apiVersion: v1
baseDomain: ${var.private_domain}
compute:
- hyperthreading: Enabled
  name: worker
  replicas: 0
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: ${var.control_plane["count"]}
metadata:
  name: ${var.name}
networking:
  clusterNetworks:
  - cidr: ${var.cluster_network_cidr}
    hostPrefix: ${var.host_prefix}
  networkType: OpenShiftSDN
  serviceNetwork:
  - ${var.service_network_cidr}
platform:
  none: {}
pullSecret: '${file(var.openshift_pull_secret)}'
sshKey: '${tls_private_key.install_ssh_key.public_key_openssh}'  
EOF
}

resource "null_resource" "write_install_config" {
  depends_on = [
    "null_resource.install_httpd"
  ]

  connection {
    type        = "ssh"
    host        = "${local.bastion_ip}"
    user        = "${var.ssh_user}"
    password    = "${var.ssh_password}"
    private_key = "${file(var.ssh_private_key_file)}"
  }

  provisioner "file" {
    content     = "${data.template_file.install_config_yaml.rendered}"
    destination = "/tmp/install-config.yaml"
  }
  
  provisioner "remote-exec" {
    inline = [
      "sudo cp /tmp/install-config.yaml /var/www/html"
    ]
  }

}

resource "null_resource" "write_ssh_key" {
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
      "mkdir -p ~${var.ssh_user}/.ssh",
      "echo '${tls_private_key.install_ssh_key.public_key_openssh}' > ~${var.ssh_user}/.ssh/id_rsa.pub",
      "echo '${tls_private_key.install_ssh_key.private_key_pem}' > ~${var.ssh_user}/.ssh/id_rsa",
      "chmod 700 ~${var.ssh_user}/.ssh",
      "chmod 600 ~${var.ssh_user}/.ssh/id_rsa.pub",
      "chmod 600 ~${var.ssh_user}/.ssh/id_rsa"
    ]
  }
}

resource "null_resource" "generate_ignition_config" {
  depends_on = [
    "null_resource.write_install_config",
    "null_resource.openshift_installer"
  ]

  triggers = {
    ignition_config = "${data.template_file.install_config_yaml.rendered}"
  }

  connection {
    type        = "ssh"
    host        = "${local.bastion_ip}"
    user        = "${var.ssh_user}"
    password    = "${var.ssh_password}"
    private_key = "${file(var.ssh_private_key_file)}"
  }

  provisioner "file" {
    content     = "${data.template_file.install_config_yaml.rendered}"
    destination = "/tmp/install-config.yaml"
  }
  
  provisioner "remote-exec" {
    inline = [
      "sudo cp /tmp/install-config.yaml /var/www/html",
      "sudo /tmp/openshift-install --dir=/var/www/html create ignition-configs",
      "sudo sed -i 's/https:/http:/g' /var/www/html/master.ign",
      "sudo sed -i 's/https:/http:/g' /var/www/html/worker.ign",
      "sudo sed -i 's/api-int.${var.name}.${var.private_domain}:22623/${var.bootstrap_ip_address}:22624/g' /var/www/html/master.ign",
      "sudo sed -i 's/api-int.${var.name}.${var.private_domain}:22623/${var.bootstrap_ip_address}:22624/g' /var/www/html/worker.ign"
    ]
  }
}

resource "null_resource" "wait_for_bootstrap_complete" {
  depends_on = [
    "vsphere_virtual_machine.bootstrap",
    "vsphere_virtual_machine.bootstrap_ds_cluster",
    "vsphere_virtual_machine.control_plane",
    "vsphere_virtual_machine.control_plane_ds_cluster",
    "null_resource.generate_ignition_config",
    "null_resource.openshift_installer"
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
      "sudo /tmp/openshift-install --dir=/var/www/html wait-for bootstrap-complete --log-level debug"
    ]
  }
}

resource "null_resource" "patch_registry_storage" {
  depends_on = [
    "null_resource.wait_for_bootstrap_complete",
    "null_resource.openshift_client"
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
      "echo \"/usr/local/bin/oc --kubeconfig=/var/www/html/auth/kubeconfig get configs.imageregistry.operator.openshift.io cluster\" > /tmp/check.sh",
      "chmod u+x /tmp/check.sh",
      "while [ ! /tmp/check.sh ]; do sleep 1; done",
      "/usr/local/bin/oc --kubeconfig=/var/www/html/auth/kubeconfig patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{\"spec\":{\"storage\":{\"emptyDir\":{}}}}'"
    ]
  }
}

resource "null_resource" "wait_for_install_complete" {
  depends_on = [
    "null_resource.patch_registry_storage",
    "null_resource.openshift_installer",
    "null_resource.patch_registry_storage"
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
      "sudo /tmp/openshift-install --dir=/var/www/html wait-for install-complete --log-level debug"
    ]
  }
}
