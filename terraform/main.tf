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
  linux_vms = {
    ans01     = { id = 511, cores = 2, mem = 2048, disk = 30, vlan = 20, ip = "10.20.0.11/24" }
    srv-lnx01 = { id = 512, cores = 2, mem = 2048, disk = 30, vlan = 20, ip = "10.20.0.12/24" }
    cl-lin01  = { id = 520, cores = 2, mem = 2048, disk = 30, vlan = 80, ip = "dhcp" }
  }
}

#network

resource "proxmox_network_linux_bridge" "vmbr101" {
  node_name = "home-server"
  name = "vmbr101"
  address = "172.16.0.1/24"
  comment = "DC-NAT"
  vlan_aware = true
}

resource "proxmox_network_linux_bridge" "vmbr102" {
  node_name = "home-server"
  name = "vmbr102"
  comment = "server-LAN"
  vlan_aware = true
}

resource "proxmox_virtual_environment_vm" "linux_vms" {
  for_each = local.linux_vms

  name = each.key
  node_name = "home-server"
  vm_id = each.value.id

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
    bridge = "vmbr102"
    model = "virtio"
    vlan_id = each.value.vlan
  }
  initialization {
    ip_config {
      ipv4 {
        address = each.value.ip
      }
    }
  }
  agent {
    enabled = true
    wait_for_ip {
      disables = true
    }
  }  
}
resource "proxmox_cloned_vm" "dc01" {
  clone = {
    source_vm_id = 3000
    full = false
  }
  name      = "dc01"
  id     = 510
  node_name = "home-server"
  network = {
    net0 = {
      bridge = "vmbr102"
      model = "virtio"
      tag = 20
    }
  }
}
