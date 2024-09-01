#!/bin/bash
set -eu
# See https://github.com/warewulf/warewulf-node-images/blob/main/rockylinux-9/Containerfile-fixed

dnf install -y epel-release dnf-plugins-core
dnf install -y "https://repos.openhpc.community/OpenHPC/3/EL_9/$(arch)/ohpc-release-3-1.el9.$(arch).rpm"
dnf config-manager --set-enabled crb
dnf copr enable cyqsimon/micro -y

# ELRepo setup for ML kernel
rpm --import "https://www.elrepo.org/RPM-GPG-KEY-elrepo.org"
dnf install -y "https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm"

dnf update -y
dnf install -y --enablerepo=elrepo-kernel kernel-ml kernel-ml-modules
dnf install -y --allowerasing --setopt=install_weak_deps=False \
  ohpc-slurm-client ipa-client \
  NetworkManager dhclient nfs-utils ipmitool openssh-clients openssh-server initscripts \
  ${PACKAGES}

dnf groupinstall 'Development Tools' --setopt=group_package_types=mandatory -y

# Open up ports for slurm, NFS, SSH, and Wireguard
cat <<EOF >/etc/firewalld/zones/public.xml
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>Public</short>
  <description></description>
  <service name="ssh"/>
  <service name="dhcpv6-client"/>
  <service name="mountd"/>
  <service name="rpc-bind"/>

  <port port="60001-65000" protocol="tcp"/> <!-- Slurm srun -->
  <port port="6818" protocol="tcp"/> <!-- Slurmd -->
  <port port="51820" protocol="udp"/> <!-- Wireguard -->
  
  <forward/>
</zone>
EOF

cat <<EOF >/etc/resolv.conf
# Overwritten at image build time, should be replaced by IPA
nameserver 1.1.1.1
EOF

dnf clean all
