data "template_file" "rhn_register_sh" {
  vars = {
    verbosity = ""

    rhel_user_name = "${var.rhn_username}"
    rhel_password  = "${var.rhn_password}"
    subscription_pool = "${var.rhn_poolid}"
  }

  template = "${file("${path.module}/templates/rhn_register.sh.tpl")}"

}

locals {
    nodes_to_register = compact(list(local.haproxy_ip,local.bastion_ip))
}

resource "null_resource" "rhn_register" {
    depends_on = [
      "vsphere_virtual_machine.haproxy",
      "vsphere_virtual_machine.haproxy_ds_cluster",
      "vsphere_virtual_machine.bastion",
      "vsphere_virtual_machine.bastion_ds_cluster"
    ]

    count = "${length(local.nodes_to_register)}"

    triggers = {
      node_list = "${join(",", local.nodes_to_register)}"
    }

    connection {
        type     = "ssh"
        host        = "${element(local.nodes_to_register, count.index)}"
        user        = "${var.ssh_user}"
        password    = "${var.ssh_password}"
        private_key = ""
    }

    provisioner "file" {
        when = "create"
        content      = "${data.template_file.rhn_register_sh.rendered}"
        destination = "/tmp/rhn_register.sh"
    }

    provisioner "remote-exec" {
        when = "create"
        inline = [
            "chmod +x /tmp/rhn_register.sh",
            "sudo /tmp/rhn_register.sh",
            "rm -f /tmp/rhn_register.sh"
        ]
    }

    provisioner "remote-exec" {
        when = "destroy"
        inline = [
            "sudo subscription-manager unregister",
        ]
    }
}

