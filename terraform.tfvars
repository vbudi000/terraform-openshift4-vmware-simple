name = "vbd-tf-ocp41"
private_domain = "csplab.local"
rhn_username = "vbudi@us.ibm.com"
rhn_password = "0nTh3B3nch!"
rhn_poolid   = "8a85f99a6cbfea02016cce73c7372fd7"

openshift_pull_secret = "./openshift_pull_secret.json"

private_netmask = "16"
lb_private_ip_address = "172.16.54.160"
bootstrap_ip_address = "172.16.54.171"
bastion_private_ip_address = "172.16.54.170"
control_plane_ip_addresses = ["172.16.54.162", "172.16.54.163", "172.16.54.164" ]
worker_ip_addresses = ["172.16.54.165", "172.16.54.166", "172.16.54.167", "172.16.54.168", "172.16.54.169" ]
private_gateway = "172.16.255.250"
private_dns_servers = ["172.16.53.250"]
dns_ip_address = "172.16.53.250"

vsphere_server = "10.1.212.26"
vsphere_datacenter = "CSPLAB"
vsphere_cluster = "Sandbox"
vsphere_resource_pool = "vbudi-lab"
private_network_label = "csplab"
datastore_cluster = "SANDBOX_TIER4"
folder = "/Sandbox/vbdocp41"

rhcos_template = "Sandbox/hc-rhosp1/rhcos-4.1.0-x86_64-vmware"
rhel_template = "Sandbox/CCCVMs/RHEL76B"
# rhel_template = "Sandbox/WebbVMs/Templates/WebbOpenShift311TemplateThin"

control_plane = {
    count = "3"
    vcpu = "8"
    memory = "16384"
}

worker = {
    count = "5"
    vcpu = "8"
    memory = "16384"
}

boot_disk = {
    disk_size = "200"
    thin_provisioned = "true"
    keep_disk_on_remove = false
    eagerly_scrub = false
}

ssh_user = "root"
ssh_password = "off2Frye!"
