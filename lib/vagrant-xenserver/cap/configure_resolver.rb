require 'tempfile'

module VagrantPlugins
  module Cap
    # edit /etc/resolv.conf
    class ConfigureResolver
      include Vagrant::Util

      def self.configure_resolver(machine, dns)
        resolv = ""
        dns.each do |line|
          resolv += "nameserver #{line}\n"
        end
        machine.communicate.tap do |comm|

          temp = Tempfile.new("vagrant")
          temp.binmode
          temp.write(resolv)
          temp.close

          comm.upload(temp.path, "/tmp/vagrant-etc-resolv.conf")
          comm.sudo("/bin/cp /tmp/vagrant-etc-resolv.conf /etc/resolv.conf")
          comm.execute("rm -f /tmp/vagrant-etc-resolv.conf")
        end
      end
    end
  end
end