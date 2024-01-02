terraform {
  required_providers {
    proxmox = {
      source = "TheGameProfi/proxmox"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true
}

resource "proxmox_vm_qemu" "vm" {
  count       = var.vm_count
  vmid        = 8000 + (count.index + 1)
  name        = "bit-${count.index + 1}"
  target_node = "pve"

  clone      = "ubuntu-cloud"
  full_clone = true
  clone_wait = 0

  os_type = "cloud-init"

  ciuser     = var.ci_user
  cipassword = var.ci_password
  sshkeys    = file(var.ci_ssh_public_key)

  cores  = 2
  memory = 2048
  agent  = 1

  bootdisk  = "scsi0"
  scsihw    = "virtio-scsi-pci"
  ipconfig0 = "ip=dhcp"

  disk {
    volume = "local-lvm:vm-${8000 + count.index + 1}-disk-0"
    size    = "8396M"
    type    = "scsi"
    storage = "local-lvm"
    backup = true
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  lifecycle {
    ignore_changes = [
      network
    ]
  }
}

resource "null_resource" "create_ansible_inventory" {
  provisioner "local-exec" {
    command = <<-EOT
      cat <<EOL > inventory.ini
      [vms]
      ${join("\n", formatlist("%s ansible_host=%s", proxmox_vm_qemu.vm.*.name, proxmox_vm_qemu.vm.*.default_ipv4_address))}
    EOT
  }

  depends_on = [ proxmox_vm_qemu.vm ]
}

resource "null_resource" "ansible" {
  provisioner "local-exec" {
    command = "sleep 180; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini -u ${var.ci_user} --private-key ${var.ci_ssh_private_key} playbook.yml"
  }
}

output "vm_info" {
  value = [
    for vm in proxmox_vm_qemu.vm : {
      hostname = vm.name
      ip-addr  = vm.default_ipv4_address
    }
  ]
}
