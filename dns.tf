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

    template = "${format("etcd-%d.%s.%s:2380", count.index, lower(var.name), lower(var.private_domain))}"
}

data "template_file" "etcd_srv_target" {
    count = "${var.control_plane["count"]}"

    template = "_etcd-server-ssl._tcp.${lower(var.name)}"
}

