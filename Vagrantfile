
Vagrant.configure(2) do |config|
  config.vm.box = 'centos/7'
  config.vm.box_check_update = false

  hosts = { 'casper01' => '192.168.99.31', 'casper02' => '192.168.99.32' }

  hosts.each do |hostname, ipaddr|
    config.vm.define hostname do |host|
      host.vm.hostname = hostname
      host.vm.network :private_network, ip: ipaddr, virtualbox__intnet: "intnet0"
      host.vm.provision :shell, path: "./provision/#{hostname}.sh"

      host.vm.provider :libvirt do |lb|
        (1..2).each do |port|
          lb.storage :file, :size => '10G'
          lb.storage :file, :size => '10G'
        end
      end
    end
  end

  config.vm.define 'hostpc' do |host|
    host.vm.hostname = 'hostpc'
    host.vm.network :private_network, ip: '192.168.99.100', virtualbox__intnet: "intnet0"
    host.vm.provision :shell, path: './provision/hostpc.sh'
  end
end
