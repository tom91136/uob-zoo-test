#!/bin/bash

## Provision script taken from https://raw.githubusercontent.com/rgl/proxmox-ve/master/example/provision.sh

set -eux

ip=$1
gw=$2
fqdn=$(hostname --fqdn)

# configure apt for non-interactive mode.
export DEBIAN_FRONTEND=noninteractive

cat >/etc/network/interfaces <<EOF

auto lo
iface lo inet loopback

auto host0
iface host0 inet dhcp

auto vmbr0
iface vmbr0 inet static
    address $ip/24
    gateway $gw
    bridge-ports host0
    bridge_stp off
    bridge_fd 0
    # WAN bridge

auto vmbr1
iface vmbr1 inet static
    address 10.10.10.2/24
    # gateway $gw     
    bridge_stp off
    bridge_fd 0
    bridge-ports none
    # LAN bridge

auto vmbr2
iface vmbr2 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    # MGMT bridge

EOF


sed -i -E "s,^[^ ]+( .*pve.*)\$,$ip\1," /etc/hosts
sed 's,\\,\\\\,g' >/etc/issue <<'EOF'

     _ __  _ __ _____  ___ __ ___   _____  __ __   _____
    | '_ \| '__/ _ \ \/ / '_ ` _ \ / _ \ \/ / \ \ / / _ \
    | |_) | | | (_) >  <| | | | | | (_) >  <   \ V /  __/
    | .__/|_|  \___/_/\_\_| |_| |_|\___/_/\_\   \_/ \___|
    | |
    |_|

EOF
cat >>/etc/issue <<EOF
    https://$ip:8006/
    https://$fqdn:8006/

EOF
iptables-save         # show current rules.
killall agetty | true # force them to re-display the issue file.

apt-get install -y cloud-guest-utils pve-edk2-firmware-aarch64
apt-get install -y parted cryptsetup htop micro
 
echo 'Proxmox.Utils.checked_command = function(o) { o(); };' >>/usr/share/pve-manager/js/pvemanagerlib.js

fstrim -av
echo "Provision complete"
