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

variable "ovmf_code" {
  type        = string
  default     = ""
  description = "Path to OVMF_CODE file"
}

variable "ovmf_vars" {
  type        = string
  default     = ""
  description = "Path to OVMF_VARS file"
}

variable "aavmf_code" {
  type        = string
  default     = ""
  description = "Path to AAVMF_CODE file"
}

variable "aavmf_vars" {
  type        = string
  default     = ""
  description = "Path to AAVMF_VARS file"
}

variable "name" {
  type = string
}

locals {
  vmf_code_path = {
    "x86_64"  = "${var.ovmf_code}"
    "aarch64" = "${var.aavmf_code}"
  }
  vmf_vars_path = {
    "x86_64"  = "${var.ovmf_vars}"
    "aarch64" = "${var.aavmf_vars}"
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
    ["-drive", "if=pflash,format=raw,id=ovmf_code,readonly=on,file=${lookup(local.vmf_code_path, var.arch, "")}"],
    ["-drive", "if=pflash,format=raw,id=ovmf_vars,file=output-${var.name}.${var.arch}/${basename(lookup(local.vmf_vars_path, var.arch, ""))}"],
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
      "cp ${lookup(local.vmf_vars_path, var.arch, "")} output-${var.name}.${var.arch}/${basename(lookup(local.vmf_vars_path, var.arch, ""))}",
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

 