#!/bin/bash

set -eu
if [ -z "$1" ]; then
    echo "Usage: $0 FILE VMID [host] [chunk_size]"
    echo "Sends a large file to remote "
    exit 1
fi
source="$1"
dest="$2"
vmid="$3"
chunk_size="${4:-1200}"
if [ ! -f "$source" ]; then echo "Source file not found: $source" && exit 1; fi
checksum="$(sha256sum <"$source" | cut -d" " -f1)"
set +e
IFS= read -rd '' content <"$source"
set -e
content_length="$(wc -m "$source" | cut -d' ' -f1)"
chunk_id=0
total_chunks="$(((content_length + chunk_size - 1) / chunk_size))"
echo "Sending $source ($content_length chars) as $total_chunks chunk(s)..."

for ((i = 0; i < content_length; i += chunk_size)); do
    chunk="${content:i:$chunk_size}"
    chunk_id=$((chunk_id + 1))
    pvesh create "/nodes/localhost/qemu/$vmid/agent/file-write" --file "$dest.$chunk_id" --content "$chunk"
    printf "\r%3d%% [%s]" "$((chunk_id * 100 / total_chunks))" "$(printf '%0.s#' $(seq 1 $chunk_id))"
done

echo ""
echo "Creating $dest on $vmid..."
qm guest exec "$vmid" -- sh -c "> $dest"
echo "Combining $dest on $vmid..."
qm guest exec "$vmid" -- sh -c "for n in \$(seq 1 1 $total_chunks); do cat \"$dest.\$n\" >> \"$dest\"; rm \"$dest.\$n\"; done"
echo "Validating $dest on $vmid..."
actual_checksum_json=$(qm guest exec "$vmid" -- sh -c "echo \$(sha256sum <\"$dest\" | cut -d' ' -f1)")
if [[ $actual_checksum_json == *"$checksum"* ]]; then
    echo "Checksum correct"
    echo "Done"
else
    echo "Checksum mismatch, exec: $actual_checksum_json" && exit 1
fi
