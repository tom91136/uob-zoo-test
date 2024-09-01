#!/bin/bash
set -euxo pipefail

# configure apt for non-interactive mode.
export DEBIAN_FRONTEND=noninteractive

# add support for the en_GB locale.
sed -i -E 's,.+(en_GB.UTF-8 .+),\1,' /etc/locale.gen
locale-gen
locale -a

# set the timezone.
ln -fs /usr/share/zoneinfo/Europe/London /etc/localtime
dpkg-reconfigure tzdata
