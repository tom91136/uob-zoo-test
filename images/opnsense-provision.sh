#!/bin/sh

set -eu

# cat <<EOF >ssh_fragment.xml
#          <ssh>
#           <noauto>1</noauto>
#           <interfaces/>
#           <kex/>
#           <ciphers/>
#           <macs/>
#           <keys/>
#           <keysig/>
#           <enabled>enabled</enabled>
#           <permitrootlogin>1</permitrootlogin>
#         </ssh>
# EOF
# sed -i '' -e '/<ssh>/r ssh_fragment.xml' -e '/<ssh>/,/<\/ssh>/d' /conf/config.xml
# rm -rf ssh_fragment.xml

opnsense-update -bkp # update first so that we have the correct version of python
# opnsense-code ports  # grab ports and install e2fsprogs, as needed by cloud-init
# (
#     cd /usr/ports/sysutils/e2fsprogs
#     make install
# )

# install cloud-init, sequence based on https://github.com/virt-lightning/freebsd-cloud-images
# curl -L -o cloud-init.tar.gz "https://github.com/canonical/cloud-init/archive/refs/tags/24.1.7.tar.gz"
# tar xf cloud-init.tar.gz
# touch /etc/rc.conf
# (
#     cd cloud-init-*
#     # e2fsprog already installed via ports, so delete dependency
#     sed -i '' '/e2fsprog/d' ./tools/build-on-freebsd
#     ./tools/build-on-freebsd
# )
# rm -rf cloud-init-* cloud-init.tar.gz

# Setup QEMU guest agent and emergency editor
echo 'autoboot_delay="0"' >>/boot/loader.conf
pkg install -y qemu-guest-agent nano
cat <<EOF >>/etc/rc.conf
qemu_guest_agent_enable="YES"
qemu_guest_agent_flags="-d -v -l /var/log/qemu-ga.log"
EOF

touch /.probe.for.growfs
