#!/bin/bash

set -eux

WAN_IFACE=${WAN_IFACE:-"eth0"}

export CONTAINER_IP=10.10.8.2
export CONTAINER_GW=10.10.8.1
export CONTAINER_PASSWD="vagrant"
export CONTAINER_HOSTNAME="pve.local"
export CONTAINER_NAME="proxmox"
export DEBIAN_VERSION="bookworm"

USER_HOME=$([ "$EUID" -eq 0 ] && eval echo "~$SUDO_USER" || echo "$HOME")
export SSH_PUBKEY_LINE=$(cat "$USER_HOME/.ssh/id_ed25519.pub")
export SSH_IDENTITY="$USER_HOME/.ssh/id_ed25519"

export VZ_DISK_SIZE=40G
export VZ_IMAGE=staging/vz.btrfs
export VZ_OPTS="loop,compress-force=zstd"
export VZ_MOUNT=staging/vz_mount
export RDS1_DISK=staging/rds1.xfs.qcow2
export RDS1_KEY="staging/luks.key"
export RDS1_PASS="vagrant"
export RDS1_DEV="/dev/nbd0"

export VZ_IMAGE=/mnt/vz.btrfs
export VZ_OPTS="loop"

function check_root() {
  if [[ $EUID -ne 0 ]]; then echo "This script must be run as root" && exit 1; fi
}

function nspawn_boot() {
  if ! mount | grep -q "$VZ_MOUNT" || true; then
    echo "Mounting $VZ_IMAGE to $VZ_MOUNT..."
    mount -o $VZ_OPTS "$VZ_IMAGE" "$VZ_MOUNT" || true
  else
    echo "$VZ_MOUNT is already mounted."
  fi
  systemd-nspawn -b -D "staging/$CONTAINER_NAME" --network-veth --hostname="$CONTAINER_HOSTNAME" \
    --property DeviceAllow='/dev/fuse rwm' \
    --bind=/dev/kvm \
    --bind="$PWD/$RDS1_KEY:/boot/luks.key" \
    --bind="$PWD/$VZ_MOUNT:/var/lib/vz/images" \
    --bind="$PWD/$RDS1_DISK:/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_rds1" \
    --console=read-only
}
export -f nspawn_boot

mkdir -p staging

case "${1:-}" in
build)
  check_root
  if [ ! -d "staging/$CONTAINER_NAME" ]; then
    debootstrap "$DEBIAN_VERSION" "staging/$CONTAINER_NAME" http://deb.debian.org/debian
  fi

  cat <<-EOF >"/etc/systemd/network/80-container-$CONTAINER_NAME.network"
[Match]
Name=ve-$CONTAINER_NAME
Driver=veth

[Network]
Address=$CONTAINER_GW/24    
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
EOF
  ;;
mkfs)
  check_root
  (
    rm -rf "$VZ_IMAGE"
    truncate -s $VZ_DISK_SIZE "$VZ_IMAGE"
    mkfs.btrfs "$VZ_IMAGE"
    mkdir -p "$VZ_MOUNT"
    mount -o loop,compress-force=zstd "$VZ_IMAGE" "$VZ_MOUNT"
    fstrim -v "$VZ_MOUNT"
    umount "$VZ_MOUNT"
  )
  (
    rm -rf "$RDS1_DISK"
    qemu-img create -f qcow2 "$RDS1_DISK" 1G
    modprobe nbd
    qemu-nbd --disconnect "$RDS1_DEV"
    qemu-nbd --connect="$RDS1_DEV" "$RDS1_DISK"

    parted -s "$RDS1_DEV" mklabel gpt || parted -s "$RDS1_DEV" mklabel gpt # first call sometime fails (!?)
    parted -s -a optimal "$RDS1_DEV" mkpart primary 0% 100%

    sync
    sleep 1

    echo -n "$RDS1_PASS" | cryptsetup luksFormat "${RDS1_DEV}p1" -
    echo -n "$RDS1_PASS" | cryptsetup luksOpen "${RDS1_DEV}p1" rds1_luks -
    openssl genrsa -out "$RDS1_KEY" 4096
    echo -n "$RDS1_PASS" | cryptsetup luksAddKey "${RDS1_DEV}p1" "$RDS1_KEY" -
    mkfs.xfs /dev/mapper/rds1_luks
    cryptsetup luksClose rds1_luks

    qemu-nbd --disconnect "$RDS1_DEV"
  )
  ;;
provision)
  check_root
  nspawn_boot &
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
  ) &
  wait
  ;;
boot)
  check_root
  chown "$SUDO_USER:$SUDO_USER" staging
  nohup bash -c nspawn_boot &> staging/boot.out &

  sleep 10
  scp -i "$SSH_IDENTITY" -o StrictHostKeychecking=no scripts/nspawn-provision.sh root@$CONTAINER_IP:/root/provision.sh
  # shellcheck disable=SC2087
  ssh -i "$SSH_IDENTITY" -o StrictHostKeychecking=no root@$CONTAINER_IP bash <<EOF
set -eux
echo "nameserver 1.1.1.1" > /etc/resolv.conf
export DEBIAN_FRONTEND=noninteractivec
bash \$HOME/provision.sh "$CONTAINER_IP" "$CONTAINER_GW"
systemctl restart networking
EOF
  ;;
poweroff)
  ssh -i "$SSH_IDENTITY" -o StrictHostKeychecking=no root@$CONTAINER_IP poweroff
  ;;
setup-tests)
  ansible-galaxy install -r requirements.yml --force
  ruby staging.rb staging/inventory.yml
  ;;
run-play)
  play=$2
  ansible-playbook -i staging/inventory.yml "$play" --extra-vars="domain=staging.local"
  ;;
esac
