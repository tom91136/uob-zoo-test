#!/bin/bash

set -eu

echo "Patching VM with name $1 for aarch64 emulation"
vm_id="$(qm list | awk "/$1/ {print \$1}")"
echo "Found VMID $vm_id"

config="/etc/pve/qemu-server/$vm_id.conf"

# Step 1: Comment out vmgenid, cpu, efidisk line which prevents boot
sed -i '/^vmgenid:/s/^/#/' "$config"
sed -i '/^cpu:/s/^/#/' "$config"
sed -i '/^efidisk0/s/^/#/' "$config" # this causes a warning but boots

# Step 2: Set serial console for display
qm set "$vm_id" --serial0=socket
qm set "$vm_id" --vga=serial0

# Step 3: Add the correct arch type
arch_line="arch: aarch64"
grep -qF -- "$arch_line" "$config" || echo "$arch_line" >>"$config"
