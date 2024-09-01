#!/bin/bash
set -euxo pipefail

# configure apt for non-interactive mode.
export DEBIAN_FRONTEND=noninteractive

# remove old kernel packages.
# NB as of pve 8.1, there's a metapackage, proxmox-kernel-6.5, then there are
#    the real kernels at proxmox-kernel-*-pve-signed (these are the ones that
#    are removed).
proxmox_kernels=$(dpkg-query -f '${Package}\n' -W 'proxmox-kernel-*-pve-signed')
for proxmox_kernel in $proxmox_kernels; do
    if [[ $proxmox_kernel != "proxmox-kernel-$(uname -r)-signed" ]]; then
        apt-get remove -y --purge $proxmox_kernel
    fi
done

# let the root user login.
cat >/etc/ssh/sshd_config.d/local.conf <<'EOF'
PermitRootLogin yes
EOF

# create a group where sudo will not ask for a password.
apt-get install -q -y sudo
groupadd -r admin
echo '%admin ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/admin

# create the vagrant user. also allow access with the insecure vagrant public key.
# NB vagrant will replace it on the first run.
groupadd vagrant
useradd -g vagrant -m vagrant -s /bin/bash
gpasswd -a vagrant admin
chmod 750 /home/vagrant
install -d -m 700 /home/vagrant/.ssh
pushd /home/vagrant/.ssh
wget -q --no-check-certificate https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant.pub -O authorized_keys
chmod 600 authorized_keys
chown -R vagrant:vagrant .
popd
 
apt-get install -y qemu-guest-agent spice-vdagent

# install rsync and sshfs to support shared folders in vagrant.
apt-get install -y rsync sshfs

# disable the DNS reverse lookup on the SSH server. this stops it from
# trying to resolve the client IP address into a DNS domain name, which
# is kinda slow and does not normally work when running inside VB.
echo UseDNS no >>/etc/ssh/sshd_config

# make sure the ssh connections are properly closed when the system is shutdown.
# NB this is needed for vagrant reload and vagrant-reload plugin.
# NB this also needs UsePAM yes in sshd_config (which is already there).
apt-get install -y libpam-systemd

# disable the graphical terminal. its kinda slow and useless on a VM.
sed -i -E 's,#(GRUB_TERMINAL\s*=).*,\1console,g' /etc/default/grub
update-grub

# reset the machine-id.
# NB systemd will re-generate it on the next boot.
# NB machine-id is indirectly used in DHCP as Option 61 (Client Identifier), which
#    the DHCP server uses to (re-)assign the same or new client IP address.
# see https://www.freedesktop.org/software/systemd/man/machine-id.html
# see https://www.freedesktop.org/software/systemd/man/systemd-machine-id-setup.html
echo '' >/etc/machine-id
rm -f /var/lib/dbus/machine-id

# reset the random-seed.
# NB systemd-random-seed re-generates it on every boot and shutdown.
# NB you can prove that random-seed file does not exist on the image with:
#       sudo virt-filesystems -a ~/.vagrant.d/boxes/proxmox-ve-amd64/0/libvirt/box.img
#       sudo guestmount -a ~/.vagrant.d/boxes/proxmox-ve-amd64/0/libvirt/box.img -m /dev/pve/root --pid-file guestmount.pid --ro /mnt
#       sudo ls -laF /mnt/var/lib/systemd
#       sudo guestunmount /mnt
#       sudo bash -c 'while kill -0 $(cat guestmount.pid) 2>/dev/null; do sleep .1; done; rm guestmount.pid' # wait for guestmount to finish.
# see https://www.freedesktop.org/software/systemd/man/systemd-random-seed.service.html
# see https://manpages.debian.org/stretch/manpages/random.4.en.html
# see https://manpages.debian.org/stretch/manpages/random.7.en.html
# see https://github.com/systemd/systemd/blob/master/src/random-seed/random-seed.c
# see https://github.com/torvalds/linux/blob/master/drivers/char/random.c
systemctl stop systemd-random-seed
rm -f /var/lib/systemd/random-seed

# clean packages.
apt-get -y autoremove
apt-get -y clean

# show the free space.
df -h /

fstrim -av