SHELL=bash
.SHELLFLAGS=-euo pipefail -c

VAR_FILE :=
VAR_FILE_OPTION := $(addprefix -var-file=,$(VAR_FILE))

build-libvirt: proxmox-ve-amd64-libvirt.box

proxmox-ve-amd64-libvirt.box: provisioners/*.sh proxmox-ve.pkr.hcl Vagrantfile.template $(VAR_FILE)
	rm -f $@
	CHECKPOINT_DISABLE=1 \
	PACKER_LOG=1 \
	PACKER_LOG_PATH=$@.init.log \
		packer init proxmox-ve.pkr.hcl
	PACKER_OUTPUT_BASE_DIR=$${PACKER_OUTPUT_BASE_DIR:-.} \
	PACKER_KEY_INTERVAL=10ms \
	CHECKPOINT_DISABLE=1 \
	PACKER_LOG=1 \
	PACKER_LOG_PATH=$@.log \
	PKR_VAR_vagrant_box=$@ \
		packer build -only=qemu.proxmox-ve-amd64 -on-error=abort -timestamp-ui $(VAR_FILE_OPTION) proxmox-ve.pkr.hcl
	@./box-metadata.sh libvirt proxmox-ve-amd64 $@

clean:
	rm -rf packer_cache $${PACKER_OUTPUT_BASE_DIR:-.}/output-proxmox-ve*

.PHONY: build-libvirt clean
