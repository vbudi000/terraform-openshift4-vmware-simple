
resource "null_resource" "openshift_installer" {
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
    "null_resource.install_httpd"
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

data "template_file" "install_config_yaml" {
  template = <<EOF
apiVersion: v1
baseDomain: ${var.domain}
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
      "sudo sed -i 's/api-int.${var.name}.${var.domain}:22623/${var.bootstrap_ip_address}:22624/g' /var/www/html/master.ign",
      "sudo sed -i 's/api-int.${var.name}.${var.domain}:22623/${var.bootstrap_ip_address}:22624/g' /var/www/html/worker.ign"
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
