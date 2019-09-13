variable "ignition_url" {
  default = ""
}

variable "name" {
}

variable "control_plane_ip_addresses" {
  type = list
  default = []
}

variable "worker_ip_addresses" {
  type = list
  default = []
}

variable "dns_ip_address" {
}

variable "bastion_private_ip_address" {
}

variable "bastion_public_ip_address" {
  default = ""
}

variable "bootstrap_ip_address" {
}

variable "lb_private_ip_address" {
}

variable "lb_public_ip_address" {
  default = ""
}

####################################
#### vSphere Access Credentials ####
####################################
variable "vsphere_server" {
  description = "vsphere server to connect to"
  default     = "___INSERT_YOUR_OWN____"
}

# Set username/password as environment variables VSPHERE_USER and VSPHERE_PASSWORD

variable "allow_unverified_ssl" {
  description = "Allows terraform vsphere provider to communicate with vsphere servers with self signed certificates"
  default     = "true"
}

##############################################
##### vSphere deployment specifications ######
##############################################

variable "vsphere_datacenter" {
  description = "Name of the vsphere datacenter to deploy to"
  default     = "___INSERT_YOUR_OWN____"
}

variable "vsphere_cluster" {
  description = "Name of vsphere cluster to deploy to"
  default     = "___INSERT_YOUR_OWN____"
}

variable "vsphere_resource_pool" {
  description = "Path of resource pool to deploy to. i.e. /path/to/pool"
  default     = "/"
}

variable "private_network_label" {
  description = "Name or label of network to provision VMs on. All VMs will be provisioned on the same network"
}

variable "public_network_label" {
  description = "Name or label of public network to provision lbs on. All VMs will be provisioned on the same network"
  default     = ""
}

variable "datastore" {
  description = "Name of datastore to use for the VMs (do not specify if datastore_cluster specified)"
  default     = ""
}

variable "datastore_cluster" {
  description = "Name of datastore cluster to use for the VMs (do not specify if datastore specified)"
  default     = ""
}

## Note
# Because of https://github.com/terraform-providers/terraform-provider-vsphere/issues/271 templates must be converted to VMs on ESX 5.5 (and possibly other)
variable "rhcos_template" {
  description = "Name of template or VM to clone for the VM creations. Tested on Ubuntu 16.04 LTS"
  default     = "___INSERT_YOUR_OWN____"
}

variable "rhel_template" {
  description = "Name of template or VM to clone for the VM creations. Tested on Ubuntu 16.04 LTS"
  default     = "___INSERT_YOUR_OWN____"
}

variable "folder" {
  description = "Name of VM Folder to provision the new VMs in. The folder will be created"
  default     = ""
}

variable "install" {
  type = map

  default = {
    vcpu   = "2"
    memory = "4096"
    disk_size   = ""
    thin_provisioned      = "true"      # True or false. Whether to use thin provisioning on the disk. Leave blank to use same as template
    eagerly_scrub         = "false"      # True or false. If set to true disk space is zeroed out on VM creation. Leave blank to use same as template
    keep_disk_on_remove   = "false" # Set to 'true' to not delete a disk on removal.
  }
}

variable "bootstrap" {
  type = map

  default = {
    vcpu   = "4"
    memory = "16384"
    disk   = 100
  }
}

variable "control_plane" {
  type = map

  default = {
    count  = "3"
    vcpu   = "8"
    memory = "16384"
  }
}

variable "worker" {
  type = map

  default = {
    count  = "3"
    vcpu   = "8"
    memory = "16384"
  }
}


variable "boot_disk" {
  type = map

  default = {
    disk_size             = "100"      # Specify size or leave empty to use same size as template.
    thin_provisioned      = "true"      # True or false. Whether to use thin provisioning on the disk. Leave blank to use same as template
    eagerly_scrub         = "false"      # True or false. If set to true disk space is zeroed out on VM creation. Leave blank to use same as template
    keep_disk_on_remove   = "false" # Set to 'true' to not delete a disk on removal.
  }
}

variable "additional_disk" {
  type = map

  default = {
    disk_size             = "100"      # Specify size or leave empty to use same size as template.
    thin_provisioned      = "true"      # True or false. Whether to use thin provisioning on the disk. Leave blank to use same as template
    eagerly_scrub         = "false"      # True or false. If set to true disk space is zeroed out on VM creation. Leave blank to use same as template
    keep_disk_on_remove   = "false" # Set to 'true' to not delete a disk on removal.
  }
}

variable "private_gateway" {
  description = "Private network gateway for the newly provisioned VMs. Leave blank to use DHCP"
}

variable "private_netmask" {
  description = "Netmask in CIDR notation when using static IPs. For example 16 or 24. Set to 0 to retrieve from DHCP"
}

variable "private_dns_servers" {
  description = "DNS Servers to configure on VMs"
}

variable "private_domain" {
}

variable "public_gateway" {
  description = "Private network gateway for the newly provisioned VMs. Leave blank to use DHCP"
  default = ""
}

variable "public_netmask" {
  description = "Netmask in CIDR notation when using static IPs. For example 16 or 24. Set to 0 to retrieve from DHCP"
  default = ""
}

variable "public_dns_servers" {
  description = "DNS Servers to configure on VMs"
  type = "list"
  default = []
}

variable "public_domain" {
  default = ""
}

variable "dns_key_name" {
  default = "rndc-key"
}

variable "dns_key_algorithm" {
  default = "hmac-md5"
}

variable "dns_key_secret" {
  default = ""
}

variable "dns_record_ttl" {
  default = 300
}

variable "ssh_user" {
  description = "Username which terraform will use to connect to newly created VMs during provisioning"
  default     = "root"
}

variable "ssh_password" {
  description = "Password which terraform will use to connect to newly created VMs during provisioning"
  default     = ""
}

variable "ssh_private_key_file" {
  description = "Location of private ssh key to connect to newly created VMs during provisioning"
  default     = "/dev/null"
}

variable "openshift_pull_secret" {
  default = ""
}

variable "cluster_network_cidr" {
  default = "10.254.0.0/16"
}

variable "host_prefix" {
  default = 24
}

variable "service_network_cidr" {
  default = "172.30.0.0/16"
}

variable "bootstrap_complete" {
  default = "false"
}

variable "rhn_username" {
  default = ""
}
variable "rhn_password" {
  default = ""
}
variable "rhn_poolid" {
  default = ""
}

variable "frontend" {
    default = ["6443", "22623", "443", "80"]
}

variable "backend" {
    default = {
        "6443" = "",
        "22623" = "",
        "443" = "",
        "80" = ""
    }
}
