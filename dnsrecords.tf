provider "dns" {
  update {
    server = "${var.bastion_ip_address}"
    key_name = "${var.dns_key_name}"
    key_algorithm = "${var.dns_key_algorithm}"
    key_secret = "${var.dns_key_secret}"
  }
}

locals {
    
    zone_name               = "${lower(var.name)}.${var.domain}."

    node_ips = compact(concat(
        list(var.bootstrap_ip_address),
        var.control_plane_ip_addresses,
        var.worker_ip_addresses,
    ))

    node_hostnames = compact(concat(
        list("${lower(var.name)}-bootstrap.${lower(var.name)}.${var.domain}"),
        formatlist("%v.%v", data.template_file.control_plane_hostname_a.*.rendered, var.domain),
        formatlist("%v.%v", data.template_file.worker_hostname_a.*.rendered, var.domain),
    ))

    a_records = zipmap(
      concat(
        list("api.${lower(var.name)}.${var.domain}"),
        list("api-int.${lower(var.name)}.${var.domain}"),
        list("*.apps.${lower(var.name)}.${var.domain}"),
        formatlist("%v.%v", data.template_file.etcd_hostname.*.rendered, var.domain)
      ),
      concat(
        list(var.bastion_ip_address),
        list(var.bastion_ip_address),
        list(var.bastion_ip_address),
        var.control_plane_ip_addresses)
    )

    srv_records = list("_etcd-server-ssl._tcp.${lower(var.name)}.${var.domain}")
    srv_record_targets = zipmap(
        data.template_file.etcd_srv_hostname.*.rendered, 
        formatlist("%v.%v", data.template_file.etcd_srv_target.*.rendered, var.domain))
  ttl = 3600
}

resource "dns_a_record_set" "node_a_record" {
  count = "${var.control_plane["count"] + var.worker["count"] + 1}"

  zone = "${local.zone_name}"
  
  # in case the caller passes fqdn, drop the zone name as we don't need it
  name = "${replace(element(local.node_hostnames, count.index), replace(".${local.zone_name}", "/\\.$/", ""), "")}"

  addresses = ["${element(local.node_ips, count.index)}"]
  ttl = "${local.ttl}"
}

resource "dns_ptr_record" "node_ptr_record" {
  count = "${var.control_plane["count"] + var.worker["count"] + 1}"

  zone = "${format("%s.in-addr.arpa.", join(".", reverse(slice(split(".", element(local.node_ips, count.index)), 0, 3))))}"
  name = "${element(split(".", element(local.node_ips, count.index)), 3)}"
  ptr = "${element(local.node_hostnames, count.index)}.${local.zone_name}"

  ttl = "${local.ttl}"
}

resource "dns_a_record_set" "other_a_record" {
  count = "${var.control_plane["count"] + 3}"

  zone = "${local.zone_name}"
  name = "${replace(element(keys(local.a_records), count.index), replace(".${local.zone_name}", "/\\.$/", ""), "")}"

  addresses = ["${element(values(local.a_records), count.index)}"]
  ttl = "${local.ttl}"
}

resource "dns_srv_record_set" "srv_record" {
  count = "${var.control_plane["count"]}"

  zone = "${local.zone_name}"

  # in case the caller passes fqdn, drop the zone name as we don't need it
  name = "${replace(element(local.srv_records, count.index), replace(".${local.zone_name}", "/\\.$/", ""), "")}"

  dynamic "srv" {
    for_each = matchkeys(
      keys(local.srv_record_targets), 
      values(local.srv_record_targets), 
      list(element(local.srv_records, count.index)))

    content {
      priority = 0
      weight = 10
      target = "${format("%s.", element(split(":", srv.value), 0))}"
      port = "${element(split(":", srv.value), 1)}"
    }
  }
}

resource "null_resource" "dns_records_done" {

  depends_on = [
    "dns_a_record_set"."node_a_record",
    "dns_a_record_set"."other_a_record",
    "dns_ptr_record"."node_ptr_record",
    "dns_srv_record_set"."srv_record",
  ]

}
