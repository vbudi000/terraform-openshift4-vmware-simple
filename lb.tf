locals {
  haproxy_ip = "${element(compact(list(var.lb_public_ip_address, var.lb_private_ip_address)), 0)}"

  backend_list = {
  "6443" = "${join(",", compact(concat(var.control_plane_ip_addresses, list(var.bootstrap_complete ? "" : var.bootstrap_ip_address))))}",
  "22623" = "${join(",", compact(concat(var.control_plane_ip_addresses, list(var.bootstrap_complete ? "" : var.bootstrap_ip_address))))}",
  "443" = "${join(",", var.worker_ip_addresses)}",
  "80" = "${join(",", var.worker_ip_addresses)}"
  }
}

resource "vsphere_virtual_machine" "haproxy" {
  count = "${var.datastore != "" ? 1 : 0}"
  folder     = "${var.folder}"

  #####
  # VM Specifications
  ####
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"

  name      = "${lower(var.name)}-haproxy"
  num_cpus  = "${var.install["vcpu"]}"
  memory    = "${var.install["memory"]}"

  ####
  # Disk specifications
  ####
  datastore_id  = "${data.vsphere_datastore.datastore.0.id}"
  guest_id      = "${data.vsphere_virtual_machine.rhel_template.guest_id}"
  scsi_type     = "${data.vsphere_virtual_machine.rhel_template.scsi_type}"

  disk {
      label            = "${lower(var.name)}-haproxy.vmdk"
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
        host_name = "${lower(var.name)}-haproxy"
        domain    = "${var.private_domain != "" ? var.private_domain : format("%s.local", var.name)}"
      }

      dynamic "network_interface" {
        for_each = compact(concat(data.vsphere_network.public_network.*.id, list(data.vsphere_network.private_network.id)))
        content {
          ipv4_address = "${element(compact(list(var.haproxy_public_ip_address, var.haproxy_private_ip_address)), network_interface.key)}"
          ipv4_netmask = 16
        }
      }

      ipv4_gateway    = "${var.public_gateway != "" ? var.public_gateway : var.private_gateway}"

      dns_server_list = "${var.private_dns_servers}"
      dns_suffix_list = list(format("%v.%v", var.name, var.private_domain), var.private_domain)
    }
  }
}

resource "vsphere_virtual_machine" "haproxy_ds_cluster" {
  count = "${var.datastore_cluster != "" ? 1 : 0}"


  folder     = "${var.folder}"

  #####
  # VM Specifications
  ####
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"

  name      = "${lower(var.name)}-haproxy"
  num_cpus  = "${var.install["vcpu"]}"
  memory    = "${var.install["memory"]}"

  ####
  # Disk specifications
  ####
  datastore_cluster_id  = "${data.vsphere_datastore_cluster.datastore_cluster.0.id}"
  guest_id      = "${data.vsphere_virtual_machine.rhel_template.guest_id}"
  scsi_type     = "${data.vsphere_virtual_machine.rhel_template.scsi_type}"

  disk {
      label            = "${lower(var.name)}-haproxy.vmdk"
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
        host_name = "${lower(var.name)}-haproxy"
        domain    = "${var.private_domain != "" ? var.private_domain : format("%s.local", var.name)}"
      }

      dynamic "network_interface" {
        for_each = compact(concat(data.vsphere_network.public_network.*.id, list(data.vsphere_network.private_network.id)))
        content {
          ipv4_address = "${element(compact(list(var.lb_private_ip_address)), network_interface.key)}"
          ipv4_netmask = 16
        }
      }

      ipv4_gateway    = "${var.public_gateway != "" ? var.public_gateway : var.private_gateway}"

      dns_server_list = "${var.private_dns_servers}"
      dns_suffix_list = list(format("%v.%v", var.name, var.private_domain), var.private_domain)
    }
  }
}

# because certificate generation is time sensitive, make sure that system clock is set to UTC to 
# match all of the RHCOS VMs
resource "null_resource" "set_systemclock_utc_haproxy" {
  depends_on = [
    "vsphere_virtual_machine.haproxy",
    "vsphere_virtual_machine.haproxy_ds_cluster"
  ]

  connection {
    type        = "ssh"
    host        = "${local.haproxy_ip}"
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

resource "null_resource" "install_haproxy" {
  depends_on = [
    "vsphere_virtual_machine.haproxy",
    "vsphere_virtual_machine.haproxy_ds_cluster",
    "null_resource.rhn_register"
  ]

  connection {
    type        = "ssh"
    host        = "${local.haproxy_ip}"
    user        = "${var.ssh_user}"
    password    = "${var.ssh_password}"
    private_key = "${file(var.ssh_private_key_file)}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo subscription-manager repos --enable='rhel-7-server-rpms'",
      "sudo yum install -y haproxy",
      "sudo systemctl enable haproxy",
    ]
  }
}

resource "null_resource" "open_ports_firewalld_haproxy" {

    count = "${length(var.frontend)}"

  depends_on = [
    "vsphere_virtual_machine.haproxy",
    "vsphere_virtual_machine.haproxy_ds_cluster"
  ]
 
  connection {
    type          = "ssh"
    host          = "${local.haproxy_ip}"
    user          = "${var.ssh_user}"
    password      = "${var.ssh_password}"
    private_key   = "${file(var.ssh_private_key_file)}"
  }

  provisioner "remote-exec" {
    when = "create"
    inline = [
            "sudo firewall-cmd --zone=public --add-port=${element(var.frontend, count.index)}/tcp",
            "sudo firewall-cmd --zone=public --add-port=${element(var.frontend, count.index)}/tcp --permanent"
    ]
  }
}

resource "null_resource" "write_ssh_key_haproxy" {
  depends_on = [
    "vsphere_virtual_machine.haproxy",
    "vsphere_virtual_machine.haproxy_ds_cluster"
  ]
 
  connection {
    type        = "ssh"
    host        = "${local.haproxy_ip}"
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

resource "null_resource" "selinux_allow" {
  connection {
    type        = "ssh"
    host        = "${local.haproxy_ip}"
    user        = "${var.ssh_user}"
    password    = "${var.ssh_password}"
    private_key = "${file(var.ssh_private_key_file)}"
  }

    provisioner "remote-exec" {
        when = "create"
        inline = [
            "sudo setsebool -P haproxy_connect_any=1"
        ]
    }
}

data "template_file" "haproxy_config_global" {
    template = <<EOF
global
    user haproxy
    group haproxy
    daemon
    maxconn 4096
EOF
}

data "template_file" "haproxy_config_defaults" {
    template = <<EOF
defaults
    mode    tcp
    balance leastconn
    timeout client      30000ms
    timeout server      30000ms
    timeout connect      3000ms
    retries 3
EOF
}

data "template_file" "haproxy_config_frontend" {
    count = "${length(var.frontend)}"

    template = <<EOF
frontend fr_server${element(var.frontend, count.index)}
  bind 0.0.0.0:${element(var.frontend, count.index)}
  default_backend bk_server${element(var.frontend, count.index)}
EOF
}

data "template_file" "haproxy_config_backend" {
    count = "${length(keys(var.backend))}"

    template = <<EOF
backend bk_server${element(keys(var.backend), count.index)}
  balance roundrobin
${join("\n", formatlist("  server srv%v %v:%v check fall 3 rise 2 maxconn 2048", split(",", lookup(local.backend_list, element(keys(local.backend_list), count.index))), split(",", lookup(local.backend_list, element(keys(local.backend_list), count.index))), element(keys(local.backend_list), count.index)))}
EOF
}

resource "null_resource" "haproxy_cfg" {
    depends_on = [
        "null_resource.install_haproxy",
        "null_resource.selinux_allow"
    ]

    triggers = {
        defaults = "${data.template_file.haproxy_config_defaults.rendered}"
        global = "${data.template_file.haproxy_config_global.rendered}"
        frontend = "${join(",", data.template_file.haproxy_config_frontend.*.rendered)}"
        backend = "${join(",", data.template_file.haproxy_config_backend.*.rendered)}"
    }

  connection {
    type        = "ssh"
    host        = "${local.haproxy_ip}"
    user        = "${var.ssh_user}"
    password    = "${var.ssh_password}"
    private_key = "${file(var.ssh_private_key_file)}"
  }

    provisioner "file" {
        content     = <<EOF
${data.template_file.haproxy_config_global.rendered}
${data.template_file.haproxy_config_defaults.rendered}
${join("\n", data.template_file.haproxy_config_frontend.*.rendered)}
${join("\n", data.template_file.haproxy_config_backend.*.rendered)}
EOF
        destination = "/tmp/haproxy.cfg"
    }

    provisioner "remote-exec" {
        inline = [
            "sudo haproxy -c -f /tmp/haproxy.cfg",
            "sudo cp /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg",
            "sudo systemctl restart haproxy"
        ]
    }
}
