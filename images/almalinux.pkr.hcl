# Derived from https://github.com/canonical/packer-maas/blob/main/ubuntu/ubuntu-cloudimg.pkr.hcl
variable "arch" {
  type = string
}

variable "image" {
  type = string
}


variable "PACKAGES" {
  type = string
}

variable "ovmf_suffix" {
  type        = string
  default     = ""
  description = "Suffix for OVMF CODE and VARS files. Newer systems such as Noble use _4M."
}

variable "name" {
  type = string
}

locals {
  uefi_imp = {
    "x86_64"  = "OVMF"
    "aarch64" = "AAVMF"
  }
  qemu_machine = {
    "x86_64"  = "accel=kvm"
    "aarch64" = "virt"
  }
  qemu_cpu = {
    "x86_64"  = "host"
    "aarch64" = "max,pauth-impdef=on"
  }
  qemu_args = {
    "x86_64"  = []
    "aarch64" = [["--accel", "tcg,thread=multi"]]
  }
}

source "null" "dependencies" {
  communicator = "none"
}

source "qemu" "almalinux" {

  iso_checksum = "none"
  iso_urls     = [var.image]

  disk_image       = true
  disk_size        = "10G"
  vm_name          = "${var.name}.${var.arch}.qcow2"
  boot_wait        = "2s"
  headless         = true
  cpus             = 2
  memory           = 2048
  format           = "qcow2"
  shutdown_command = "sudo poweroff"
  qemu_binary      = "qemu-system-${var.arch}"
  qemu_img_args {
    create = ["-F", "qcow2"]
  }
  output_directory = "output-${var.name}.${var.arch}"
  qemuargs = concat([
    ["-machine", "${lookup(local.qemu_machine, var.arch, "")}"],
    ["-cpu", "${lookup(local.qemu_cpu, var.arch, "")}"],
    ["-device", "virtio-gpu-pci"],
    ["-drive", "if=pflash,format=raw,id=ovmf_code,readonly=on,file=/usr/share/${lookup(local.uefi_imp, var.arch, "")}/${lookup(local.uefi_imp, var.arch, "")}_CODE${var.ovmf_suffix}.fd"],
    ["-drive", "if=pflash,format=raw,id=ovmf_vars,file=output-${var.name}.${var.arch}/${lookup(local.uefi_imp, var.arch, "")}_VARS.fd"],
    ["-drive", "file=output-${var.name}.${var.arch}/${var.name}.${var.arch}.qcow2,format=qcow2"],
    ["-drive", "file=output-${var.name}.${var.arch}/seeds-cloudimg.iso,format=raw"],
  ], lookup(local.qemu_args, var.arch, ""))
  # use_backing_file = true

  ssh_username = "almalinux"
  ssh_password = "almalinux" # see user-data-cloudimg file
  ssh_port     = 22
  ssh_timeout  = "1000s"
}

build {
  name    = "${var.name}.deps"
  sources = ["source.null.dependencies"]

  provisioner "shell-local" {
    inline = [
      "cp /usr/share/${lookup(local.uefi_imp, var.arch, "")}/${lookup(local.uefi_imp, var.arch, "")}_VARS.fd output-${var.name}.${var.arch}/${lookup(local.uefi_imp, var.arch, "")}_VARS.fd",
      "cloud-localds output-${var.name}.${var.arch}/seeds-cloudimg.iso user-data-cloudimg meta-data"
    ]
    inline_shebang = "/bin/bash -e"
  }
}

build {

  name    = "${var.name}"
  sources = ["source.qemu.almalinux"]

  provisioner "shell" {
    environment_vars = ["PACKAGES=${var.PACKAGES}"]
    scripts          = ["${var.name}-provision.sh"]
    execute_command  = "chmod +x {{ .Path }};export {{ .Vars }};sudo -E {{ .Path }}"
  }

  post-processor "shell-local" {
    inline = [
      "IMG_FMT=qcow2",
      "SOURCE=almalinux.${var.arch}",
      "ROOT_PARTITION=1",
      "DETECT_BLS_BOOT=1",
      "OUTPUT=${var.name}.${var.arch}.qcow2",
    ]
    inline_shebang = "/bin/bash -e"
  }
}

 