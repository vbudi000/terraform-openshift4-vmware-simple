locals {
  mask        = "${var.netmask}"
  gw          = "${var.gateway}"

  ignition_url = "${var.ignition_url != "" ? "${var.ignition_url}" : "http://${var.bastion_ip_address}:88" }"
}

data "ignition_file" "bootstrap_hostname" {
  filesystem = "root"
  path       = "/etc/hostname"
  mode       = "420"

  content {
    content = "${var.name}-bootstrap.${var.name}.${lower(var.domain)}"
  }
}

# HWADDR=${upper(vsphere_virtual_machine.bootstrap.attributes.network_interface.mac_address)}
# HWADDR=${upper(format("00:50:55:10:%2x:%2x",element(split(".",var.bootstrap_ip_address),2),element(split(".",var.bootstrap_ip_address),3)))}
data "ignition_file" "bootstrap_static_ip" {
  filesystem = "root"
  path       = "/etc/sysconfig/network-scripts/ifcfg-ens192"
  mode       = "420"

  content {
    content = <<EOF
TYPE=Ethernet
BOOTPROTO=none
NAME="Wired connection 1"
DEVICE=ens192
ONBOOT=yes
IPADDR=${var.bootstrap_ip_address}
PREFIX=${local.mask}
GATEWAY=${local.gw}
DOMAIN=${lower(var.name)}.${var.domain}
DNS1=${var.bastion_ip_address}
SEARCH="${lower(var.name)}.${lower(var.domain)} ${lower(var.domain)}"
EOF
  }
}

data "ignition_file" "control_plane_hostname" {
  count = "${var.control_plane["count"]}"

  filesystem = "root"
  path       = "/etc/hostname"
  mode       = "420"

  content {
    content  = "${element(data.template_file.control_plane_hostname.*.rendered, count.index)}.${lower(var.name)}.${lower(var.domain)}"
  }
}

# HWADDR=${upper(element(vsphere_virtual_machine.control_plane,count.index).attributes.network_interface.mac_address)}
data "ignition_file" "control_plane_static_ip" {
  count = "${var.control_plane["count"]}"

  filesystem = "root"
  path       = "/etc/sysconfig/network-scripts/ifcfg-ens192"
  mode       = "420"

  content {
    content = <<EOF
TYPE=Ethernet
BOOTPROTO=none
NAME="Wired connection 1"
DEVICE=ens192
ONBOOT=yes
IPADDR=${element(var.control_plane_ip_addresses, count.index)}
PREFIX=${local.mask}
GATEWAY=${local.gw}
DOMAIN=${lower(var.name)}.${var.domain}
DNS1=${var.bastion_ip_address}
SEARCH="${lower(var.name)}.${lower(var.domain)} ${lower(var.domain)}"
EOF
  }
}

data "ignition_file" "resolv_conf" {
  filesystem = "root"
  path       = "/etc/resolv.conf"
  mode       = "644"

  content {
    content  = <<EOF
nameserver ${var.bastion_ip_address}
search ${var.name}.${var.domain}
EOF
  }
}


data "ignition_file" "worker_hostname" {
  count = "${var.worker["count"]}"

  filesystem = "root"
  path       = "/etc/hostname"
  mode       = "420"

  content {
    content  = "${element(data.template_file.worker_hostname.*.rendered, count.index)}.${lower(var.name)}.${lower(var.domain)}"
  }
}

# HWADDR=${upper(element(vsphere_virtual_machine.worker,count.index).attributes.network_interface.mac_address)}
data "ignition_file" "worker_static_ip" {
  count = "${var.worker["count"]}"

  filesystem = "root"
  path       = "/etc/sysconfig/network-scripts/ifcfg-ens192"
  mode       = "420"

  content {
    content = <<EOF
TYPE=Ethernet
BOOTPROTO=none
NAME="Wired connection 1"
DEVICE=ens192
ONBOOT=yes
IPADDR=${element(var.worker_ip_addresses, count.index)}
PREFIX=${local.mask}
GATEWAY=${local.gw}
DOMAIN=${lower(var.name)}.${var.domain}
DNS1=${var.bastion_ip_address}
SEARCH="${lower(var.name)}.${lower(var.domain)} ${lower(var.domain)}"
EOF
  }
}

data "ignition_systemd_unit" "restart" {
  name = "restart.service"

  content = <<EOF
[Unit]
ConditionFirstBoot=yes
[Service]
Type=idle
ExecStart=/sbin/reboot
[Install]
WantedBy=multi-user.target
EOF
}

data "ignition_config" "bootstrap_ign" {
  append {
    source = "${local.ignition_url}/bootstrap.ign"
  }

  systemd = [
    "${data.ignition_systemd_unit.restart.id}",
  ]

  files = [
    "${data.ignition_file.bootstrap_hostname.id}",
    "${data.ignition_file.bootstrap_static_ip.id}",
    "${data.ignition_file.resolv_conf.id}"
  ]
}

data "ignition_config" "control_plane_ign" {
  count = "${var.control_plane["count"]}"

  append {
    source = "${local.ignition_url}/master.ign"
  }

  systemd = [
    "${data.ignition_systemd_unit.restart.id}",
  ]

  files = [
    "${data.ignition_file.control_plane_hostname.*.id[count.index]}",
    "${data.ignition_file.control_plane_static_ip.*.id[count.index]}",
    "${data.ignition_file.resolv_conf.id}"
  ]
}

data "ignition_config" "worker_ign" {
  count = "${var.worker["count"]}"

  append {
    source = "${local.ignition_url}/worker.ign"
  }

  systemd = [
    "${data.ignition_systemd_unit.restart.id}",
  ]

  files = [
    "${data.ignition_file.worker_hostname.*.id[count.index]}",
    "${data.ignition_file.worker_static_ip.*.id[count.index]}",
    "${data.ignition_file.resolv_conf.id}"
  ]
}
