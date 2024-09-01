This builds an up-to-date [Proxmox VE](https://www.proxmox.com/en/proxmox-ve) Vagrant Base Box.
The source and docs are heavily derived from https://github.com/rgl/proxmox-ve but with non-KVM source removed.
The default filesystem is also set to BTRFS to facilitate compression. 

Currently this targets Proxmox VE 8.

# Usage

Create the base box as described in the section corresponding to your provider.
If you want to troubleshoot the packer execution see the `.log` file that is created in the current directory.
Access the [Proxmox Web Interface](https://10.10.10.2:8006/) with the default `root` user and password `vagrant`.

## libvirt

Create the base box:

```bash
make build-libvirt
```

Add the base box as suggested in make output:

```bash
vagrant box add -f proxmox-ve-amd64 proxmox-ve-amd64-libvirt.box
```

Start the example vagrant environment with:

```bash
cd example
vagrant up --no-destroy-on-error --provider=libvirt
```

## Variables override

Some properties of the virtual machine and the Proxmox VE installation can be overridden.
Take a look at `proxmox-ve.pkr.hcl`, `variable` blocks, to get an idea which values can be
overridden. Do not override `iso_url` and `iso_checksum` as the `boot_command`s might be
tied to a specific Proxmox VE version. Also take care when you decide to override `country`.

Create the base box:

```bash
make build-libvirt VAR_FILE=example.pkrvars.hcl
```

The following content of `example.pkrvars.hcl`:

* sets the initial disk size to 128 GB
* sets the initial memory to 4 GB
* sets the Packer output base directory to /dev/shm
* sets the country to Germany (timezone is updated by Proxmox VE installer) and changes
  the keyboard layout back to "U.S. English" as this is needed for the subsequent
  `boot_command` statements
* sets the hostname to pve-test.example.local
* uses all default shell provisioners (see [`./provisioners`](./provisioners)) and a
  custom one for german localisation

```hcl
disk_size = 128 * 1024
memory = 4 * 1024
output_base_dir = "/dev/shm"
step_country = "Ger<wait>m<wait>a<wait>n<wait><enter>"
step_hostname = "pve-test.example.local"
step_keyboard_layout = "<end><up><wait>"
shell_provisioner_scripts = [
  "provisioners/apt_proxy.sh",
  "provisioners/upgrade.sh",
  "provisioners/network.sh",
  "provisioners/localisation-de.sh",
  "provisioners/reboot.sh",
  "provisioners/provision.sh",
]
```