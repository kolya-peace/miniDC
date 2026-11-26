terraform {
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "~> 0.123.1" }
  }

}

provider "proxmox" {
  endpoint  = var.server_ip
  api_token = var.api_key
  insecure = true
  ssh {
    agent    = true
    username = "root"
  }
}

locals {
  hosts     = { for h in yamldecode(file("${path.module}/../topology.yml")).hosts : h.name => h }
}
#network

resource "proxmox_network_linux_bridge" "vmbr101" {
  node_name = "home-server"
  name = "vmbr101"
  address = "172.16.0.254/24"
  comment = "DC-NAT"
  vlan_aware = true
}

resource "proxmox_network_linux_bridge" "vmbr102" {
  node_name = "home-server"
  name = "vmbr102"
  comment = "OPNsense --> GNS3"
  vlan_aware = true
}
resource "proxmox_network_linux_bridge" "vmbr103" {
  node_name = "home-server"
  name = "vmbr103"
  comment = "ServerLAN"
  vlan_aware = true
}

resource "proxmox_network_linux_vlan" "vlan20" {
  node_name = "home-server"
  name = "vmbr103.20"
  interface = "vmbr103"
  vlan = 20
  address = "10.10.20.254/24"


  comment = "MGMT interface"
}

resource "proxmox_virtual_environment_vm" "OPNsense" {
  acpi                                 = true
  bios                                 = "seabios"
  boot_order                           = ["scsi0", "ide2", "net0"]
  delete_unreferenced_disks_on_destroy = true
  description                          = null
  hook_script_file_id                  = null
  keyboard_layout                      = "en-us"
  kvm_arguments                        = null
  mac_addresses                        = ["BC:24:11:60:89:42", "BC:24:11:45:16:36"]
  machine                              = null
  migrate                              = false
  name                                 = "OPNsense"
  network_device = [{
    bridge       = "vmbr101"
    disconnected = false
    firewall     = false
    enabled = true
    mac_address  = "BC:24:11:60:89:42"
    model        = "e1000"
    mtu          = 0
    queues       = 0
    rate_limit   = 0
    trunks       = ""
    vlan_id      = 0
    }, {
    bridge       = "vmbr102"
    disconnected = false
    enabled      = true
    firewall     = false
    mac_address  = "BC:24:11:45:16:36"
    model        = "virtio"
    mtu          = 0
    queues       = 0
    rate_limit   = 0
    trunks       = ""
    vlan_id      = 0
  }]
  node_name           = "home-server"
  on_boot             = false
  pool_id             = null
  protection          = false
  purge_on_destroy    = true
  reboot              = false
  reboot_after_update = true
  scsi_hardware       = "virtio-scsi-single"
  started             = true
  stop_on_destroy     = false
  tablet_device       = true
  tags                = ["dc"]
  template            = false
  timeout_clone       = 1800
  timeout_create      = 1800
  timeout_migrate     = 1800
  timeout_reboot      = 1800
  timeout_shutdown_vm = 1800
  timeout_start_vm    = 1800
  timeout_stop_vm     = 300
  vm_id               = 502
  cdrom {
    file_id   = "local:iso/OPNsense-26.7-dvd-amd64.iso"
    interface = "ide2"
  }
  cpu {
    affinity     = null
    architecture = null
    cores        = 2
    flags        = []
    hotplugged   = 0
    limit        = 0
    numa         = false
    sockets      = 1
    type         = "x86-64-v2-AES"
  }
  disk {
    aio               = "io_uring"
    backup            = true
    cache             = "none"
    datastore_id      = "local"
    discard           = "ignore"
    file_format       = "qcow2"
    file_id           = null
    import_from       = null
    interface         = "scsi0"
    iothread          = true
    path_in_datastore = "502/vm-502-disk-0.qcow2"
    queues            = 0
    replicate         = true
    serial            = null
    size              = 12
    ssd               = false
  }
  memory {
    dedicated      = 2048
    floating       = 0
    hugepages      = null
    keep_hugepages = false
    shared         = 0
  }
  operating_system {
    type = "l26"
  }
}

resource "proxmox_virtual_environment_vm" "linux_vms" {
  for_each = local.hosts

  name = each.key
  node_name = "home-server"
  vm_id = each.value.vmid
  tags = ["dc", "terraform"]
  clone {
    vm_id = 1000
    full = false
  }

  cpu { cores = each.value.cores }
  memory { dedicated = each.value.mem }
  disk {
      datastore_id = "local"
      interface    = "scsi0"
      size         = each.value.disk
    }
  network_device {
    bridge = "vmbr103"
    model = "virtio"
    vlan_id = each.value.vlan
  }
  initialization {
    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.ip == "dhcp" ? null : cidrhost(each.value.ip, 1)
      }
    }
    user_account {
      username = "user"
      keys = [trimspace(file("~/.ssh/id_rsa.pub"))]
    }
  }
  agent {
    enabled = true
    wait_for_ip {
      disabled = true
    }
  }  
}
resource "proxmox_cloned_vm" "dc01" {
  tags = ["dc", "terraform"]
  clone = {
    source_vm_id = 3000
    full = false
  }
  name      = "dc01"
  id     = 510
  node_name = "home-server"
  network = {
    net0 = {
      bridge = "vmbr103"
      model = "virtio"
      tag = 20
    }
  }
}
