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

resource "proxmox_virtual_environment_vm" "linux_vms" {
  for_each = local.hosts

  name = each.key
  node_name = "home-server"
  vm_id = each.value.vmid
  tags = ["terraform", "DC"]

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
  tags = ["terraform", "DC"]
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
