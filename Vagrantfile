require_relative 'staging'

ENV['VAGRANT_DEFAULT_PROVIDER'] = 'libvirt'
ENV['ANSIBLE_NOCOWS'] = '1'
ENV['ANSIBLE_STDOUT_CALLBACK'] = 'yaml'

PVE_IP = '10.10.10.2'.freeze
STORAGE_POOL = 'local-btrfs'

Vagrant.require_version '>= 1.8.0'
Vagrant.configure(2) do |config|
  config.vm.define 'pve' do |pve|
    pve.vm.box = 'proxmox-ve-amd64'
    pve.vm.hostname = 'pve.local'
    pve.vm.synced_folder '.', '/vagrant', disabled: true
    pve.vm.provider :libvirt do |lv, _config|
      # See https://vagrant-libvirt.github.io/vagrant-libvirt/configuration.html
      lv.qemu_use_session = false
      lv.memory = Staging::VM_MEMORY_GB * 1024
      lv.cpus = Staging::VM_CPU
      lv.cpu_mode = 'host-passthrough'
      lv.nested = true
      lv.keymap = 'pt'
      lv.machine_virtual_size = Staging::VM_ROOT_DISK_SIZE_GB
      lv.storage :file, size: Staging::VM_RDS1_DISK_SIZE_GB, serial: 'rds1', bus: 'scsi'
    end
  end

  config.vm.network :private_network,
                    ip: PVE_IP,
                    auto_config: false,
                    libvirt__dhcp_enabled: false,
                    libvirt__forward_mode: 'none'

  config.vm.provision :shell, path: 'scripts/vagrant-provision.sh', args: PVE_IP
  config.vm.provision 'reboot', type: 'shell', inline: 'echo Rebooting', reboot: true

  def host_inventory_block(ip)
    {
      "ansible_host": ip,
      "ansible_port": 22,
      "ansible_user": 'root',
      "ansible_ssh_private_key_file": Staging::SSH_PRIVATE_KEY
    }
  end

  inventory_dir = File.join(File.dirname(__FILE__), '.vagrant/provisioners/ansible/inventory')
  FileUtils.mkdir_p(inventory_dir)
  Staging.write_inventory(
    pve_ip: PVE_IP,
    storage_pool: STORAGE_POOL,
    extra_hosts: {},
    host_common_hash: {},
    path: File.join(inventory_dir, 'extra_inventory.yml')
  )

  def ansible_provision(config, name, extra_vars)
    config.vm.provision name, type: 'ansible' do |ansible|
      ansible.verbose = 'v'
      ansible.limit = 'all'
      ansible.playbook = "playbook-#{name}.yml"
      ansible.extra_vars = extra_vars
      ansible.raw_arguments = Shellwords.shellsplit(ENV['ANSIBLE_ARGS']) if ENV['ANSIBLE_ARGS']
    end
  end

  ansible_provision(config, 'vm-router', Staging.common_vars(STORAGE_POOL))
  ansible_provision(config, 'vm-idm', Staging.common_vars(STORAGE_POOL))
  ansible_provision(config, 'vm-mgmt', Staging.common_vars(STORAGE_POOL))
  ansible_provision(config, 'vm-login', Staging.common_vars(STORAGE_POOL))

  ansible_provision(config, 'svc-idm', Staging.common_vars(STORAGE_POOL))
  ansible_provision(config, 'svc-mgmt', Staging.common_vars(STORAGE_POOL))

  ansible_provision(config, 'task-sync-images', Staging.common_vars(STORAGE_POOL))
  ansible_provision(config, 'task-sync-nodes', Staging.common_vars(STORAGE_POOL))
  ansible_provision(config, 'task-sync-users', Staging.common_vars(STORAGE_POOL))

  ansible_provision(config, 'svc-login', Staging.common_vars(STORAGE_POOL))
  ansible_provision(config, 'vm-compute', Staging.common_vars(STORAGE_POOL))
  ansible_provision(config, 'task-tests', Staging.common_vars(STORAGE_POOL))

  ansible_provision(config, 'all', Staging.common_vars(STORAGE_POOL))
end
