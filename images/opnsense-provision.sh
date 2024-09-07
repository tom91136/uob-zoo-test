#!/bin/sh

set -eu
 
df -h
opnsense-update -bkp # update first so that we have the correct version of python
df -h
 
# Setup QEMU guest agent and emergency editor
echo 'autoboot_delay="0"' >>/boot/loader.conf
pkg install -y qemu-guest-agent nano
cat <<EOF >>/etc/rc.conf
qemu_guest_agent_enable="YES"
qemu_guest_agent_flags="-d -v -l /var/log/qemu-ga.log"
EOF

fsck_ffs -E /

touch /.probe.for.growfs
