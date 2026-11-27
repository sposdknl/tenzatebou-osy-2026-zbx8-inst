Vagrant.configure("2") do |config|
  config.vm.box = "bento/debian-13"
  config.vm.hostname = "tenzatebou-zbx8"
  config.ssh.insert_key = false

  config.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1"
  config.vm.network "forwarded_port", guest: 22, host: 2211, host_ip: "127.0.0.1", id: "ssh"

  config.vm.provider "virtualbox" do |vb|
    vb.name = "tenzatebou-deb13-zbx8"
    vb.memory = 2048
    vb.cpus = 2
  end

  config.vm.provision "file", source: "scripts/configure-hosts.php", destination: "/tmp/configure-hosts.php"
  config.vm.provision "file", source: "Zabbix/export/sposdk.cz_hosts.yaml", destination: "/tmp/sposdk.cz_hosts.yaml"
  config.vm.provision "shell", path: "scripts/install.sh", binary: false
end
