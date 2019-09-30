data "template_file" "etcd_hostname" {
    count = "${var.control_plane["count"]}"

    template = "${format("etcd-%d.%s", count.index, lower(var.name))}"
}

data "template_file" "control_plane_hostname" {
    count = "${var.control_plane["count"]}"

    template = "${format("%s-master%02d", lower(var.name), count.index + 1)}"
}

data "template_file" "control_plane_hostname_a" {
    count = "${var.control_plane["count"]}"

    template = "${format("%s.%s", element(data.template_file.control_plane_hostname.*.rendered, count.index), lower(var.name))}"
}

data "template_file" "worker_hostname" {
    count = "${var.worker["count"]}"

    template = "${format("%s-worker%02d", lower(var.name), count.index + 1)}"
}

data "template_file" "worker_hostname_a" {
    count = "${var.worker["count"]}"

    template = "${format("%s.%s", element(data.template_file.worker_hostname.*.rendered, count.index), lower(var.name))}"
}


data "template_file" "etcd_srv_hostname" {
    count = "${var.control_plane["count"]}"

    template = "${format("etcd-%d.%s.%s:2380", count.index, lower(var.name), lower(var.domain))}"
}

data "template_file" "etcd_srv_target" {
    count = "${var.control_plane["count"]}"

    template = "_etcd-server-ssl._tcp.${lower(var.name)}"
}

resource "null_resource" "install_bind" {
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
      "sudo yum install -y bind bind-utils"
    ]
  }
}

resource "null_resource" "open_ports_firewalld_bind" {
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
      "sudo firewall-cmd --zone=public --add-port=53/tcp",
      "sudo firewall-cmd --zone=public --add-port=53/tcp --permanent",
      "sudo firewall-cmd --zone=public --add-port=53/udp",
      "sudo firewall-cmd --zone=public --add-port=53/udp --permanent"
    ]
  }
}

locals {
  ip_addrs = var.datastore_cluster == "" ? vsphere_virtual_machine.bastion.0.guest_ip_addresses : vsphere_virtual_machine.bastion_ds_cluster.0.guest_ip_addresses
  bind_ip = local.bastion_ip

  # assume the default reverse zone is a Class C
  default_reverse_zone = "${format("%s.in-addr.arpa", join(".", reverse(slice(split(".", var.bastion_ip_address), 0, 3))))}"

  reverse_zone = local.default_reverse_zone
  forward_zone = "${var.name}.${var.domain}"

}


data "template_file" "named_conf_rndc_key" {
    template = <<EOF
key "${var.dns_key_name}" {
	algorithm ${var.dns_key_algorithm};
	secret "${var.dns_key_secret}";
};
EOF
}

data "template_file" "named_conf_allow_query" {
    # allow everyone in the private subnet to query
    template = <<EOF
acl askers {
	any;
};
EOF
}

data "template_file" "named_conf_allow_update" {
    # allow anyone to update -- yeah this is dangerous :(
    template = <<EOF
acl updaters {
	any;
};
EOF
}

data "template_file" "named_conf_options" {
    template = <<EOF
options
{
	// Put files that named is allowed to write in the data/ directory:
	directory 		"/var/named";		// "Working" directory

	listen-on port 53	{ any; };

	forwarders {
${join("\n", formatlist("\t\t%v;", var.upstream_dns_servers))}
	};

	recursion yes;
	allow-query		{ askers; };

	/* In RHEL-7 we use /run/named instead of default /var/run/named
	   so we have to configure paths properly. */
	pid-file "/run/named/named.pid";
	session-keyfile "/run/named/session.key";

	managed-keys-directory "/var/named/dynamic";
};
EOF
}

data "template_file" "named_conf_forward_zone" {
	template = <<EOF
zone "${local.forward_zone}" {
	type master;
	file "/var/named/db.${local.forward_zone}";
	allow-update { key "${var.dns_key_name}"; };
	notify yes;
    forwarders {};
};
EOF
}

data "template_file" "named_conf_reverse_zone" {
	template = <<EOF
zone "${local.reverse_zone}" {
	type master;
	file "/var/named/db.${local.reverse_zone}";
	allow-update { key "${var.dns_key_name}"; };
	notify yes;
    forwarders {};
};
EOF
}

resource "null_resource" "named_conf" {
    depends_on = [
        "null_resource.install_bind",
    ]

    triggers = {
        named_conf_rndc_key = "${data.template_file.named_conf_rndc_key.rendered}"
        named_conf_allow_query = "${data.template_file.named_conf_allow_query.rendered}"
        named_conf_allow_update = "${data.template_file.named_conf_allow_update.rendered}"
        named_conf_options = "${data.template_file.named_conf_options.rendered}"
        named_conf_forward_zone = "${data.template_file.named_conf_forward_zone.rendered}"
        named_conf_reverse_zone = "${data.template_file.named_conf_reverse_zone.rendered}"
    }

    connection {
        type        = "ssh"
        host          = "${local.bind_ip}"
        user          = "${var.ssh_user}"
        password      = "${var.ssh_password}"
        private_key   = "${file(var.ssh_private_key_file)}"
    }

    provisioner "file" {
        content     = <<EOF
${data.template_file.named_conf_rndc_key.rendered}
${data.template_file.named_conf_allow_query.rendered}
${data.template_file.named_conf_allow_update.rendered}
${data.template_file.named_conf_options.rendered}
${data.template_file.named_conf_forward_zone.rendered}
${data.template_file.named_conf_reverse_zone.rendered}
EOF
        destination = "/tmp/named.conf"
    }

    provisioner "remote-exec" {
        inline = [
			"if [ ! -f /etc/named.conf.orig ]; then sudo cp /etc/named.conf /etc/named.conf.orig; fi",
            "sudo mv /tmp/named.conf /etc/named.conf",
			"sudo chown root:named /etc/named.conf",
            "sudo chmod 640 /etc/named.conf",
            "sudo named-checkconf /etc/named.conf"
        ]
    }
}

data "template_file" "forward_zone_file" {
# put myself as "ns.<forward_zone" but nothing else
	template = <<EOF
$ORIGIN ${local.forward_zone}.
$TTL 86400
@         IN  SOA  ns.${local.forward_zone}.  hostmaster.${local.forward_zone}. (
              2001062501  ; serial
              21600       ; refresh after 6 hours
              3600        ; retry after 1 hour
              604800      ; expire after 1 week
              86400 )     ; minimum TTL of 1 day
          IN  NS  ns.${local.forward_zone}.
ns        IN  A   ${var.bastion_ip_address}
EOF
}

data "template_file" "reverse_zone_file" {
	# add PTR to myself and that's it
	template = <<EOF
$ORIGIN ${local.reverse_zone}.
$TTL 86400
@  IN  SOA  ns.${local.forward_zone}.  hostmaster.${local.forward_zone}. (
       2001062501  ; serial
       21600       ; refresh after 6 hours
       3600        ; retry after 1 hour
       604800      ; expire after 1 week
       86400 )     ; minimum TTL of 1 day
;
@  NS   ns.${local.forward_zone}.
;
${element(split(".", var.bastion_ip_address), 3)}   IN  PTR  ns.${local.forward_zone}.

EOF
}

resource "null_resource" "forward_zone_file" {
    depends_on = [
        "null_resource.install_bind",
    ]

    triggers = {
		forward_zone_file = "${data.template_file.forward_zone_file.rendered}"
    }

    connection {
        type        = "ssh"
        host          = "${local.bind_ip}"
        user          = "${var.ssh_user}"
        password      = "${var.ssh_password}"
        private_key   = "${file(var.ssh_private_key_file)}"
    }

    provisioner "file" {
        content     = <<EOF
${data.template_file.forward_zone_file.rendered}
EOF
        destination = "/tmp/db.${local.forward_zone}"
    }

    provisioner "remote-exec" {
        inline = [
            "sudo mv /tmp/db.${local.forward_zone} /var/named/db.${local.forward_zone}",
			"sudo chown root:named /var/named/db.${local.forward_zone}",
            "sudo chmod 640 /var/named/db.${local.forward_zone}",
            "sudo named-checkconf -z /etc/named.conf"
        ]
    }
}

resource "null_resource" "reverse_zone_file" {
    depends_on = [
        "null_resource.install_bind",
    ]

    triggers = {
		reverse_zone_file = "${data.template_file.reverse_zone_file.rendered}"
    }

    connection {
        type        = "ssh"
        host          = "${local.bind_ip}"
        user          = "${var.ssh_user}"
        password      = "${var.ssh_password}"
        private_key   = "${file(var.ssh_private_key_file)}"
    }

    provisioner "file" {
        content     = <<EOF
${data.template_file.reverse_zone_file.rendered}
EOF
        destination = "/tmp/db.${local.reverse_zone}"
    }

    provisioner "remote-exec" {
        inline = [
            "sudo mv /tmp/db.${local.reverse_zone} /var/named/db.${local.reverse_zone}",
			"sudo chown root:named /var/named/db.${local.reverse_zone}",
            "sudo chmod 640 /var/named/db.${local.reverse_zone}",
            "sudo named-checkconf -z /etc/named.conf"
        ]
    }
}

resource "null_resource" "start_named" {
    depends_on = [
        "null_resource.named_conf",
        "null_resource.forward_zone_file",
        "null_resource.reverse_zone_file",
    ]

    connection {
        type        = "ssh"
        host          = "${local.bind_ip}"
        user          = "${var.ssh_user}"
        password      = "${var.ssh_password}"
        private_key   = "${file(var.ssh_private_key_file)}"
    }

    provisioner "file" {
        content     = <<EOF
${data.template_file.reverse_zone_file.rendered}
EOF
        destination = "/tmp/db.${local.reverse_zone}"
    }

    provisioner "remote-exec" {
        inline = [
            "sudo systemctl enable named",
            "sudo systemctl start named",
        ]
    }
}
