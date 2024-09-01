#!/bin/bash

set -eu

extract_wwclient_for_arch() {
    local arch="$1"
    local dest="$2"

    mkdir -p "$dest"
    wd="$(mktemp -d)"
    (
        cd "$wd"
        dnf download "warewulf-ohpc.$arch"
        rpm2cpio warewulf-ohpc*."$arch".rpm | cpio -idm

        cp "./srv/warewulf/overlays/wwinit/warewulf/wwclient" "$dest/wwclient"
        file "$dest/wwclient"
    )
    rm -rf "$wd"
}

arch="$1"
extract_wwclient_for_arch "$arch" "/srv/warewulf/overlays/arch-$arch/warewulf"
wwctl overlay build
