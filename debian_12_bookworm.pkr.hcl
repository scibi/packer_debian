packer {
  required_plugins {
    proxmox = {
      version = " >= 1.1.6"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_api_password" {
  type      = string
  default = ""
  sensitive = true
}

variable "proxmox_api_token" {
  type      = string
  default = ""
  sensitive = true
}

variable "proxmox_api_user" {
  type = string
}

variable "proxmox_host" {
  type = string
}

variable "proxmox_node" {
  type = string
}

variable "vm_name" {
  type    = string
  default = "debian-12.2.0-amd64"
}

variable "vm_id" {
  type    = number
  default = 2001
}

variable "iso_url" {
  type    = string
  default = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.2.0-amd64-netinst.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha512:11d733d626d1c7d3b20cfcccc516caff2cbc57c81769d56434aab958d4d9b3af59106bc0796252aeefede8353e2582378e08c65e35a36769d5cf673c5444f80e"
}

variable "iso_storage_pool" {
  type    = string
  default = "local"
}

variable "disk_storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "cloud_init_storage_pool" {
  type    = string
  default = "local"
}

variable "proxy_url" {
  type    = string
  default = ""
}

variable "use_github" {
  type    = bool
  default = false
}

variable "http_interface" {
  type = string
  default = "enp88s0"
}

variable "root_password" {
  type = string
  # Some random password used only when not using buildin http server
  default = "ov6SjkaQo7gk"
}


variable "net_bridge" {
  type    = string
  default = "vmbr0"
}
variable "net_vlan_id" {
  type    = string
  default = ""
}

variable "net_ip_addr" {
  type = string
}
variable "net_netmask" {
  type = string
}
variable "net_gateway" {
  type = string
}
variable "net_nameservers" {
  type = string
}

source "proxmox-iso" "debian-12-template" {
  proxmox_url = "https://${var.proxmox_host}/api2/json"
  username    = "${var.proxmox_api_user}"
  password    = "${var.proxmox_api_password}"
  token       = "${var.proxmox_api_token}"
  node        = "${var.proxmox_node}"

  insecure_skip_tls_verify = true

  boot_iso {
    type              = "scsi"
    iso_download_pve  = true
    iso_url           = "${var.iso_url}"
    iso_checksum      = "${var.iso_checksum}"
    iso_storage_pool  = "${var.iso_storage_pool}"
    unmount = true
  }


  vm_name = "${var.vm_name}"
  vm_id   = "${var.vm_id}"
  # Right now tags are not supported and have to be added manualy
  # Required change is already merged: https://github.com/hashicorp/packer-plugin-proxmox/commit/956f37b8d409a182b146dfb68e6cad83f7cde304
  # tags    = "template"

  memory   = "2048"
  cores    = "2"
  sockets  = "1"
  cpu_type = "host"
  tags     = "template"

  os = "l26"

  network_adapters {
    bridge   = "${var.net_bridge}"
    firewall = false
    model    = "virtio"
    vlan_tag = "${var.net_vlan_id}"
  }

  disks {
    storage_pool = "${var.disk_storage_pool}"
    type         = "scsi"
    disk_size    = "5G"
    format       = "raw"
    io_thread    = true
  }

  template_description = "Built from ${basename(var.iso_url)} on ${formatdate("YYYY-MM-DD hh:mm:ss ZZZ", timestamp())}"
  scsi_controller      = "virtio-scsi-single"

  boot_command = [
    "<esc><wait>",
    "auto ",
    "net.ifnames=0 ",
    "netcfg/disable_autoconfig=true ",
    "${var.net_ip_addr != "" ? format("netcfg/get_ipaddress=%s ", var.net_ip_addr) : ""}",
    "${var.net_netmask != "" ? format("netcfg/get_netmask=%s ", var.net_netmask) : ""}",
    "${var.net_gateway != "" ? format("netcfg/get_gateway=%s ", var.net_gateway) : ""}",
    "${var.net_nameservers != "" ? format("netcfg/get_nameservers=%s ", var.net_nameservers) : ""}",
    "netcfg/confirm_static=true ",
    "url=${var.use_github ? "https://raw.githubusercontent.com/scibi/packer_debian/main/http" : "http://{{ .HTTPIP }}:{{ .HTTPPort }}"}/preseed_bookworm_separate_var_log${var.use_github ? "_pub" : ""}.cfg ",
    "${var.use_github && var.proxy_url != "" ? format("http_proxy=%s ", var.proxy_url) : ""}",
#    "url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "--<enter>"
  ]
  boot_wait = "10s"
  http_content = {
    "/preseed_bookworm_separate_var_log.cfg" = templatefile("${path.root}/http/preseed_bookworm_separate_var_log.cfg", { proxy = "${var.use_github && var.proxy_url != "" ? var.proxy_url : ""}", root_password = var.root_password })
  }
  http_port_min = "8000"
  http_port_max = "8000"
  http_interface = "${var.http_interface}"

  cloud_init              = true
  cloud_init_storage_pool = "${var.cloud_init_storage_pool}"

  ssh_password = "${var.root_password}"
  ssh_username = "root"
  ssh_timeout  = "30m"
}

# a build block invokes sources and runs provisioning steps on them. The
# documentation for build blocks can be found here:
# https://www.packer.io/docs/templates/hcl_templates/blocks/build
build {
  sources = ["source.proxmox-iso.debian-12-template"]

  provisioner "file" {
    destination = "/etc/cloud/cloud.cfg"
    source      = "resources/cloud.cfg"
  }

  provisioner "file" {
    destination = "/etc/network/interfaces"
    content     = <<-EOF
      # This file describes the network interfaces available on your system
      # and how to activate them. For more information, see interfaces(5).
      
      source /etc/network/interfaces.d/*
    EOF
  }

}
