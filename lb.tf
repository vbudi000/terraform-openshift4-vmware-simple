locals {
  backend_list = {
  "6443" = "${join(",", compact(concat(var.control_plane_ip_addresses, list(var.bootstrap_complete ? "" : var.bootstrap_ip_address))))}",
  "22623" = "${join(",", compact(concat(var.control_plane_ip_addresses, list(var.bootstrap_complete ? "" : var.bootstrap_ip_address))))}",
  "443" = "${join(",", var.worker_ip_addresses)}",
  "80" = "${join(",", var.worker_ip_addresses)}"
  }
}

resource "null_resource" "install_haproxy" {
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
      "sudo yum install -y haproxy",
      "sudo systemctl enable haproxy"
    ]
  }
}

resource "null_resource" "open_ports_firewalld_haproxy" {

  count = "${length(var.frontend)}"

  depends_on = [
    "null_resource.install_haproxy"
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
            "sudo firewall-cmd --zone=public --add-port=${element(var.frontend, count.index)}/tcp",
            "sudo firewall-cmd --zone=public --add-port=${element(var.frontend, count.index)}/tcp --permanent"
    ]
  }
}

resource "null_resource" "selinux_allow" {
  depends_on = [
    "null_resource.install_haproxy"
  ]
  connection {
    type        = "ssh"
    host        = "${local.bastion_ip}"
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
        "null_resource.install_haproxy"
    ]

    triggers = {
        defaults = "${data.template_file.haproxy_config_defaults.rendered}"
        global = "${data.template_file.haproxy_config_global.rendered}"
        frontend = "${join(",", data.template_file.haproxy_config_frontend.*.rendered)}"
        backend = "${join(",", data.template_file.haproxy_config_backend.*.rendered)}"
    }

  connection {
    type        = "ssh"
    host        = "${local.bastion_ip}"
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
