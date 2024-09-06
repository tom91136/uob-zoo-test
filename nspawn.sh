#!/bin/bash

set -eux

if [[ $EUID -ne 0 ]]; then echo "This script must be run as root" && exit 1; fi

CONTAINER_IP=10.10.8.2
CONTAINER_GW=10.10.8.1
WAN_IFACE=eth0   # $(route -n| grep '^default' | grep -o '[^ ]*$')
WAN_IFACE=enp9s0 # $(route -n| grep '^default' | grep -o '[^ ]*$')

CONTAINER_PASSWD="vagrant"
CONTAINER_HOSTNAME="pve.local"
CONTAINER_NAME="proxmox"
DEBIAN_VERSION="bookworm"
USER_HOME="$(eval echo "~$SUDO_USER")"
SSH_PUBKEY_LINE=$(cat "$USER_HOME/.ssh/id_ed25519.pub")
SSH_IDENTITY="$USER_HOME/.ssh/id_ed25519"

mkdir -p staging

if [ "${1:-}" != "skip-build" ]; then
  if [ ! -d "staging/$CONTAINER_NAME" ]; then
    debootstrap "$DEBIAN_VERSION" "staging/$CONTAINER_NAME" http://deb.debian.org/debian
  fi

  cat <<-EOF >"/etc/systemd/network/80-container-$CONTAINER_NAME.network"
[Match]
Name=ve-$CONTAINER_NAME
Driver=veth

[Network]
Address=$CONTAINER_GW/24    
# LinkLocalAddressing=yes
DHCPServer=yes
IPMasquerade=ipv4

[DHCPServer]
PoolOffset=150
PoolSize=50
EmitDNS=yes
DNS=1.1.1.1
EOF

  systemctl restart systemd-networkd

  sysctl -w net.ipv4.ip_forward=1
  iptables -t nat -A POSTROUTING -o $WAN_IFACE -j MASQUERADE
  iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -A FORWARD -i ve-+ -o $WAN_IFACE -j ACCEPT
  iptables -A INPUT -i ve-+ -p udp -m udp --dport 67 -j ACCEPT

  cat <<-EOF >"staging/$CONTAINER_NAME/etc/systemd/network/80-container-host0.network"
[Match]
Virtualization=container
Name=host0

[Network]
DNS=1.1.1.1
Address=$CONTAINER_IP/24
Gateway=$CONTAINER_GW
EOF

  cat <<-EOF >"staging/$CONTAINER_NAME/etc/systemd/system/create-fuse-node.service"
[Unit]
Description=Create /dev/fuse device node
DefaultDependencies=no
Before=systemd-udevd.service
ConditionPathExists=!/dev/fuse

[Service]
Type=oneshot
ExecStart=/bin/mknod -m 666 /dev/fuse c 10 229
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
EOF

  time systemd-nspawn -D "staging/$CONTAINER_NAME" --pipe --hostname="$CONTAINER_HOSTNAME" /bin/bash <<-EOF
set -eux
export DEBIAN_FRONTEND=noninteractive
rm -rf /etc/apt/sources.list.d/pve-enterprise.list
apt-get update
apt-get -y install wget htop micro rsyslog python3 openssh-server traceroute tcpdump

SSH_CONFIG="/etc/ssh/sshd_config"
# Check if the PermitRootLogin line is present and set correctly
if grep -q "^#*PermitRootLogin" "\$SSH_CONFIG"; then
  sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "\$SSH_CONFIG"
else
  echo "PermitRootLogin yes" >> "\$SSH_CONFIG"
fi

mkdir -p \$HOME/.ssh
rm -rf \$HOME/.ssh/authorized_keys # in case PVE touched it already
echo "$SSH_PUBKEY_LINE" > \$HOME/.ssh/authorized_keys
/lib/systemd/systemd-sysv-install enable ssh

echo "$CONTAINER_HOSTNAME" > /etc/hostname
if ! grep -q "$CONTAINER_IP $CONTAINER_HOSTNAME ${CONTAINER_HOSTNAME%.*}" /etc/hosts; then
  echo "$CONTAINER_IP $CONTAINER_HOSTNAME ${CONTAINER_HOSTNAME%.*}" >> /etc/hosts
fi

REPO_LINE="deb [arch=amd64] http://download.proxmox.com/debian/pve $DEBIAN_VERSION pve-no-subscription"
if ! grep -qF "\$REPO_LINE" /etc/apt/sources.list.d/pve-install-repo.list 2>/dev/null; then
  echo "\$REPO_LINE" > /etc/apt/sources.list.d/pve-install-repo.list
fi

GPG_FILE="/etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg"
GPG_URL="https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg"
if [ ! -f "\$GPG_FILE" ]; then
  wget "\$GPG_URL" -O "\$GPG_FILE"
fi

apt-get -y update
apt-get -y full-upgrade
echo "root:$CONTAINER_PASSWD" | chpasswd

ln -sf /lib/systemd/system/systemd-networkd.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service
ln -sf /etc/systemd/system/create-fuse-node.service /etc/systemd/system/sysinit.target.wants/create-fuse-node.service
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# apt-get install -y proxmox-ve postfix open-iscsi chrony || true 
# ip addr add $CONTAINER_IP/24 dev host0
# ip route add default via $CONTAINER_GW
EOF
else
  echo "Skipping build"
fi

function provision() {
  size=40G
  vz_image=staging/vz.btrfs
  vz_mount=staging/vz_mount
  (
    rm -rf "$vz_image"
    truncate -s $size "$vz_image"
    mkfs.btrfs "$vz_image"
    mkdir -p "$vz_mount"
    mount -o loop,compress-force=zstd "$vz_image" "$vz_mount"
    fstrim -v "$vz_mount"
  )

  rds1_disk=staging/rds1.xfs.qcow2
  rds1_password="vagrant"
  rds1_dev="/dev/nbd0"
  (
    rm -rf "$rds1_disk"
    qemu-img create -f qcow2 "$rds1_disk" 1G
    modprobe nbd
    qemu-nbd --connect="$rds1_dev" "$rds1_disk"

    parted -s "$rds1_dev" mklabel gpt || parted -s "$rds1_dev" mklabel gpt # first call sometime fails (!?)
    parted -s -a optimal "$rds1_dev" mkpart primary 0% 100%

    echo -n "$rds1_password" | cryptsetup luksFormat "${rds1_dev}p1" -
    echo -n "$rds1_password" | cryptsetup luksOpen "${rds1_dev}p1" rds1_luks -
    openssl genrsa -out "staging/luks.key" 4096
    echo -n "$rds1_password" | cryptsetup luksAddKey "${rds1_dev}p1" "staging/luks.key" -
    mkfs.xfs /dev/mapper/rds1_luks
    cryptsetup luksClose rds1_luks

    qemu-nbd --disconnect "$rds1_dev"
  )

  trap cleanup INT
  cleanup() {
    umount "$vz_mount" || true
    rm -rf "$vz_mount" || true
  }
  PROVISION_SCRIPT=scripts/nspawn-provision.sh
  (
    systemd-nspawn -b -D "staging/$CONTAINER_NAME" --network-veth --hostname="$CONTAINER_HOSTNAME" \
      --property DeviceAllow='/dev/fuse rwm' \
      --bind=/dev/kvm \
      --bind="$PWD/staging/luks.key:/boot/luks.key" \
      --bind="$PWD/$vz_mount:/var/lib/vz/images" \
      --bind="$PWD/$rds1_disk:/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_rds1" \
      --console=read-only #
  ) &
  (
    sleep 10
    # ip route add 10.10.10.0/24 via 10.10.8.1
    scp -i "$SSH_IDENTITY" -o StrictHostKeychecking=no $PROVISION_SCRIPT root@$CONTAINER_IP:/root/provision.sh
    # shellcheck disable=SC2087
    ssh -i "$SSH_IDENTITY" -o StrictHostKeychecking=no root@$CONTAINER_IP bash <<EOF
set -eux
echo "nameserver 1.1.1.1" > /etc/resolv.conf
export DEBIAN_FRONTEND=noninteractivec
bash \$HOME/provision.sh $CONTAINER_IP $CONTAINER_GW
systemctl restart networking
echo "Provision complete"
EOF

    chown "$SUDO_USER:$SUDO_USER" staging

    sudo -u "$SUDO_USER" bash <<EOF
echo "Running as $SUDO_USER"
/home/tom/.local/bin/ansible-galaxy install -r requirements.yml --force
ruby staging.rb staging/inventory.yml
rm staging/success
if /home/tom/.local/bin/ansible-playbook -i staging/inventory.yml playbook-all.yml --extra-vars="domain=staging.local"; then
  touch staging/success
fi
ssh -i "$SSH_IDENTITY" -o StrictHostKeychecking=no root@$CONTAINER_IP poweroff 
EOF
  ) &
  wait
  cleanup
}

(
  systemd-nspawn -b -D "staging/$CONTAINER_NAME" --network-veth --hostname="$CONTAINER_HOSTNAME" \
    --property DeviceAllow='/dev/fuse rwm' \
    --bind=/dev/kvm \
    --console=read-only #
) &
(
  sleep 10
  ssh -i "$SSH_IDENTITY" -o StrictHostKeychecking=no root@$CONTAINER_IP bash <<'EOF'
set -eux
echo "nameserver 1.1.1.1" > /etc/resolv.conf
export DEBIAN_FRONTEND=noninteractivec
if dpkg -l | grep -qw proxmox-ve; then
  echo "proxmox-ve is already installed"
else
  sleep 1
  apt-get install -y proxmox-ve postfix open-iscsi chrony
  rm -rf /etc/apt/sources.list.d/pve-enterprise.list
fi
poweroff
EOF
  provision
) &
wait

echo "All Done"

if [ ! -f "staging/success" ]; then
  echo "Provision failed: no success found"
  exit 1
fi
