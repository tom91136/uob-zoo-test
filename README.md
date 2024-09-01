# UoB Zoo Mk II

This repo contains a fully automated test and build environment of the UoB HPC Zoo.

### Development environment setup

This section is written against a Fedora host environment, you may need to adjust accordingly for other Linux distro.

1. Vagrant

    ```shell
    sudo dnf install @vagrant libvirt-devel
    sudo systemctl enable --now libvirtd
    sudo gpasswd -a ${USER} libvirt
    newgrp libvirt # enable group for current shell, logout to apply globally
    vagrant plugin install vagrant-libvirt
    ```

    For more details on setting Vagrant and libvirt, see <https://developer.fedoraproject.org/tools/vagrant/vagrant-libvirt.html>.

2. Ansible >= 2.5 (`import_role`, etc)

    Install Ansible via pip:

    ```shell
    sudo dnf install python3-pip
    python3 -m pip install --user ansible
    ```

    See <https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html> for more installation methods.

3. Optional: Ruby development

    To setup VSCode compatible LSP for Ruby:

    ```shell
    sudo dnf install ruby-devel
    gem install solargraph
    # Append $HOME/bin to PATH
    ```

    Then install the Ruby Solargraph VSCode plugin, enable the formatting option in settings.


ansible-galaxy install -r requirements.yml


vagrant provision --provision-with=ansible-pve
vagrant provision --provision-with=ansible-ohpc
