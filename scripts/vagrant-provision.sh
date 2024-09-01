#!/bin/bash

## Provision script taken from https://raw.githubusercontent.com/rgl/proxmox-ve/master/example/provision.sh

set -eux

ip=$1
fqdn=$(hostname --fqdn)

# configure apt for non-interactive mode.
export DEBIAN_FRONTEND=noninteractive

# make sure the local apt cache is up to date.
while true; do
    apt-get update && break || sleep 5
done

# configure the network for NATting.
# ifdown vmbr0
# ifdown vmbr1

cat >/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    # WAN

auto eth1
iface eth1 inet manual
    # LAN

auto vmbr0
iface vmbr0 inet dhcp
    # address $ip
    # netmask 255.255.255.0
    bridge_ports eth0
    bridge_stp off
    bridge_fd 0
    # WAN bridge
    # # enable IP forwarding. needed to NAT and DNAT.
    # post-up   echo 1 >/proc/sys/net/ipv4/ip_forward
    # # NAT through eth0.
    # post-up   iptables -t nat -A POSTROUTING -s '$ip/24' ! -d '$ip/24' -o eth0 -j MASQUERADE
    # post-down iptables -t nat -D POSTROUTING -s '$ip/24' ! -d '$ip/24' -o eth0 -j MASQUERADE

auto vmbr1
iface vmbr1 inet static
    address $ip
    netmask 255.255.255.0
    bridge_ports eth1
    bridge_stp off
    bridge_fd 0
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
# ifup vmbr0
# ifup vmbr1
# ifup eth1
iptables-save         # show current rules.
killall agetty | true # force them to re-display the issue file.

# extend the main partition to the end of the disk and extend the
# pve/root and pve/data logical volume to use all the free space.
apt-get install -y cloud-guest-utils pve-edk2-firmware-aarch64
if growpart /dev/sda 3; then
    btrfs filesystem resize max /
fi

disk_password="vagrant"
apt-get install -y parted cryptsetup htop micro 
parted /dev/sdb mklabel gpt
parted -a optimal /dev/sdb mkpart primary 0% 100%
echo -n "$disk_password" | cryptsetup luksFormat /dev/sdb1 -
echo -n "$disk_password" | cryptsetup luksOpen /dev/sdb1 sdb1_luks -

openssl genrsa -out /boot/luks.key 4096
chmod 600 /boot/luks.key
echo -n "$disk_password" | cryptsetup luksAddKey /dev/sdb1 /boot/luks.key -

mkfs.xfs /dev/mapper/sdb1_luks
cryptsetup luksClose sdb1_luks

echo "zram" >/etc/modules-load.d/zram.conf
echo 'KERNEL=="zram0", ATTR{disksize}="28G" RUN="/sbin/mkswap /dev/zram0", TAG+="systemd"' >/etc/udev/rules.d/99-zram.rules
echo "/dev/zram0 none swap defaults,pri=10 0 0" >>/etc/fstab

# disable the "You do not have a valid subscription for this server. Please visit www.proxmox.com to get a list of available options."
# message that appears each time you logon the web-ui.
# NB this file is restored when you (re)install the pve-manager package.
echo 'Proxmox.Utils.checked_command = function(o) { o(); };' >>/usr/share/pve-manager/js/pvemanagerlib.js

sudo sed -i '/btrfs.*defaults/s/defaults/defaults,compress-force=zstd/' /etc/fstab

fstrim -av

echo "Provision complete"
