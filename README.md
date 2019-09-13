# terraform-openshift4-vmware
Terraform to provision Openshift 4.x in VMware VMs using User Provided Infrastructure (UPI)

In this example we provisioned Openshift 4.x in VMware using modular approach.  Two load balancers are provisioned using the [HAProxy Load Balancer](https://github.com/ibm-cloud-architecture/terraform-lb-haproxy-vmware) module, and DNS records are created using an existing DNS server (bind) and [DDNS update](https://github.com/ibm-cloud-architecture/terraform-dns-rfc2136) module.  

In non-PoC and non-test scenarios, these two modules may be swapped out for manual or automated procedures that configure an external load balancer or DNS server, respectively.  Specifically, DNS update may be swapped out for [DNS zonefile](https://github.com/ibm-cloud-architecture/terraform-dns-zonefile) module for manual import, for example.

## Architecture

Openshift 4.x using User-provided infrastructure

![Openshift 4 architecture](media/openshift4-arch.png)

Openshift 4 has a unique bootstrap process where a bootstrap VM is initially created with a machine config server hosting the bootstrap ignition configurations for the rest of the cluster.  Our terraform procedure roughly works like:

1. bastion node created, which contains a small webserver (httpd).  Base Ignition files are generated for each node type (bootstrap, master/control plane, and worker) and served through by the webserver.  These ignition files embed the initial TLS certs used to bootstrap kubelets into the Openshift cluster.
2. control plane load balancer created in a VM forwarding traffic on port `6443` (Openshift API) and `22623` (machine config server) to the bootstrap and all control plane VMs
3. DNS entries are created for each node (A and PTR records), and also DNS entries for the API server, etcd, and SRV records are created.
4. The bootstrap node is created, with an ignition file in the vApp properties that configures a static IP and hostname pointing at the bastion node to retrieve the rest of the cluster.  The bootstrap node starts the machine config server on port `22623`.
5. The control plane nodes are also created with static IPs and hostnames pointing at the bastion node to get the rest of the control plane ignition.  That ignition points it at the control plane load balancer on port `22623`, or the machine config server that the bootstrap node starts up.
6. The control plane receive their ignition files from the machine config server and start an etcd cluster.
7. The bootstrap nodes start up the Openshift API components that connect to the etcd cluster started on the control plane nodes.
8. The bootstrap node provisions the cluster version operator that provisions the rest of the components in the Openshift cluster.
9. The control plane  and worker nodes add themselves to the Openshift cluster and start up the Openshift API components.
10. The bootstrap node shuts down the Openshift API components, as the control plane and worker node continue on as an Openshift cluster.

Once the bootstrap node shuts down the API components, it can be removed from the load balancer and deleted.

## Prerequisites 

1. RedHat CoreOS OVA is required, import into vSphere from [here](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.1/latest/rhcos-4.1.0-x86_64-vmware.ova).  Import into vSphere and converted to template.
2. A RHEL template used for bastion VM, and haproxy load-balancer.  These templates should have a valid subscription to RHEL.
3. Existing DNS server set up to allow dynamic DNS updates from the VM that terraform runs from.
4. Openshift pull secret, saved as a json file, from [here](https://cloud.redhat.com/openshift/install).

## Variables

|Variable Name|Description|Default Value|
|-------------|-----------|-------------|
|vsphere_server|vSphere Server FQDN/IP Address|-|
|vsphere_cluster|vSphere Cluter|-|
|vsphere_datacenter|vSphere Datacenter|-|
|vsphere_resource_pool|vSphere Resource Pool|-|
|network_label|Name of Network for OCP Nodes|-|
|public_network_label|Name of Network to place HAProxy LBs|-|
|datastore|vSphere Datastore to deploy to. specify one of `datastore` or `datastore_cluster`|-|
|datastore_cluster|vSphere Datastore clusterto deploy to. specify one of `datastore` or `datastore_cluster`|-|
|rhcos_template|vSphere Template to use for RHCOS (all Openshift cluster nodes)|-|
|rhel_template|vSphere Template to use for RHEL (HAProxy LBs and Installer node)|-|
|folder|vSphere Folder to put all VMs under|-|
|name|Name of cluster, which affects VM naming.  this also ends up being the subdomain of the cluster (i.e. all `<name>`.`<domain>` is the cluster domain|-|
|domain|Base Domain.|-|
|machine_cidr|subnet for network|-|
|installer_ip_address|IP address for bastion|-|
|bootstrap_ip_address|IP address for bootstrap node|-|
|control_plane_ip_addresses|IP address for control plane nodes, a list, must specify same number as `control_plane["count"]`|-|
|worker_ip_addresses|IP address for worker nodes, must specify same number as `worker["count"]`|-|
|network|network for all VMs|-|
|gateway|default gateway for all VMs|-|
|dns_servers|list of DNS servers for all VMs, a list of just one.|-|
|ssh_user|SSH user.  Must have passwordless sudo access|-|
|ssh_password|Password for `ssh_user`.  Only used here to copy ssh keys to vms|-|
|install|A map variable for configuration of Install node|See sample variables.tf|
|bootstrap|A map variable for configuration of Bootstrap node|See sample variables.tf|
|control_plane|A map variable for configuration of Control Plane nodes|See sample variables.tf|
|worker|A map variable for configuration of Worker nodes|See sample variables.tf|
|boot_disk|A map variable for configuration of boot disk for all openshift nodes|See sample variables.tf|
|additional_disk|A map variable for configuration of additional disk for all openshift nodes|See sample variables.tf|
|dns_key_name|For DDNS update|-|
|dns_key_algorithm|For DDNS update|-|
|dns_key_secret|For DDNS update|-|
|dns_record_ttl|For DDNS update|-|
|openshift_pull_secret|Filename of json contents of openshift pull secret|-|
|cluster_network_cidr|Pod network address space|`10.254.0.0/16`|
|service_network_cidr|Service network address space|`172.30.0.0/16`|
|host_prefix|Subnet length for pod network on each host|`24`|

## `terraform.tfvars` example

```
name = "jkwong-ocp41"
domain = "my-network.com"

openshift_pull_secret = "./openshift_pull_secret.json"

machine_cidr = "192.168.100.0/24"
control_plane_ip_address = "192.168.100.60"
app_lb_ip_address = "192.168.100.61"
bootstrap_ip_address = "192.168.100.56"
bastion_ip_address = "192.168.100.62"
control_plane_ip_addresses = ["192.168.100.53", "192.168.100.54", "192.168.100.55" ]
worker_ip_addresses = ["192.168.100.58", "192.168.100.59" ]
gateway = "192.168.100.1"
dns_servers = ["192.168.100.2"]

vsphere_server = "my-vsphere.my-network.com"
vsphere_datacenter = "dc1"
vsphere_cluster = "cluster1"
vsphere_resource_pool = "openshift_rp"
network_label = "network1"
datastore_cluster = "ds-cluster1"
folder = "jkwong_ocp41"

rhcos_template = "rhcos-latest"
rhel_template = "rhel-7.6-template"

control_plane = {
    count = "3"
    vcpu = "8"
    memory = "16384"
}

worker = {
    count = "2"
    vcpu = "8"
    memory = "16384"
}

boot_disk = {
    disk_size = "100"
    thin_provisioned = "false"
    keep_disk_on_remove = false
    eagerly_scrub = false
}

dns_key_name = "rndc-key."
dns_key_algorithm = "hmac-md5"
dns_key_secret = "my-secret"
dns_record_ttl = 300

ssh_user = "user"
ssh_password = "passw0rd"
```

