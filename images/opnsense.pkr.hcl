variable "opnsense_image" {
  type = string
}

source "qemu" "opnsense" {
  boot_command = [
    # boot installer
    "<wait60>",
    # login
    "installer<enter><wait>", # user
    "opnsense<enter><wait5>", # password
    # navigate installer 
    "<enter><wait>", # select default keymap
    "<down><wait><enter><wait5>", # option 2: Install UFS
    "<enter><wait>", # select disk: vtbd0
    "y",             # confirm destroy
    "<wait300>",     # wait for installer to finish
    "<down><wait><enter>", # option 2: reboot 
    "<wait60>",      # wait for reboot
    # initial boot
    "root<enter>",                           # user
    "opnsense<enter>",                       # password
    "<wait>8<enter>",                        # select option 8: console
    "<wait10>dhclient vtnet0<enter><wait15>", # setup dhcp
    "echo 'PasswordAuthentication yes' >> /usr/local/etc/ssh/sshd_config<enter>",
    "echo 'PermitRootLogin yes' >> /usr/local/etc/ssh/sshd_config<enter>",
    "service openssh onestart<enter><wait>"
  ]

  iso_checksum = "none"
  iso_urls     = [var.opnsense_image]

  vm_name          = "opnsense.qcow2"
  headless         = true
  accelerator      = "kvm"
  cpus             = 2
  memory           = 2048
  disk_size        = 4096
  format           = "qcow2"
  boot_wait        = "5s"
  shutdown_command = "poweroff"

  ssh_username = "root"
  ssh_password = "opnsense"
  ssh_port     = 22
  ssh_timeout  = "1000s"
}


build {
  sources = [
    "source.qemu.opnsense",
  ]

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; env {{ .Vars }} {{ .Path }}"
    scripts         = ["opnsense-provision.sh"]
  }
  # provisioner "breakpoint" {
  #   disable = false
  # }
}

 