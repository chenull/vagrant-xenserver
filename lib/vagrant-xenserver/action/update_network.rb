require "log4r"
require "xmlrpc/client"
require "vagrant-xenserver/util/uploader"
require "rexml/document"
require "json"

module VagrantPlugins
  module XenServer
    module Action
      # This action check if there is configuration change in Vagrantfile
      # This will ensure the network configuration for a VM matches the
      # configuration in the Xenserver Host
      class UpdateNetwork
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant::xenserver::actions::update_network")
        end

        def call(env)
          @logger.info("Check if network configuration has been changed since the last VM up")
          myvm = env[:machine].id

          # Get all Networks
          networks = env[:xc].call("network.get_all_records", env[:session])["Value"]

          changed_vifs = {}
          unchanged_vifs = {}

          # Get currently configured vifs from Xenserver
          vifs = env[:xc].call("VM.get_VIFs", env[:session], myvm)["Value"]
          vifs.each do |vif|
            # Get vif record
            vif_rec = env[:xc].call("VIF.get_record", env[:session], vif)["Value"]
            next if vif_rec["device"].to_i == 0

            # note the device number
            eth_n = "eth#{vif_rec["device"].to_s}".to_sym

            # Find what network name_label is it
            (netref, netrec) = networks.find { |ref, net| ref == vif_rec["network"] }

            change = env[:vifs].select {
              |eth, option| option[:network] == netrec["name_label"] &&
                            eth.to_s == "eth#{vif_rec['device']}"
            }
            if change.empty?
              changed_vifs["eth#{vif_rec['device']}".to_sym] = {
                :ref => vif,
                :network => netrec["name_label"]
              }
              # Check if this eth is defined in Vagrantfile
              if not env[:vifs].keys.include? eth_n
                # Destroy VIF
                @logger.info("#{eth_n}: Deleting #{eth_n} on #{netrec["name_label"]}...")
                vif_destroy = env[:xc].call("VIF.destroy", env[:session], vif)
              end
            else
              # note it
              unchanged_vifs["eth#{vif_rec['device']}".to_sym] = vif
            end
          end

          # placeholder to new interfaces
          #new_vifs = {}

          # Loop through the new env[:vifs] from Vagrantfile, apply the change
          env[:vifs].each do |eth, option|
            if unchanged_vifs.keys.include? eth.to_sym
              @logger.info("#{eth}: on network #{option[:network]}. No changes detected ...")
            else
              (net_ref, net_rec) = networks.find { |ref, net| net['name_label'].upcase == option[:network].upcase }

              if changed_vifs.keys.include? eth
                # Modify VIF
                @logger.info("#{eth}: change detected. Modify network from #{changed_vifs[eth][:network]} to #{net_rec['name_label']}")
                # Destroy it first
                vif_destroy = env[:xc].call("VIF.destroy", env[:session], changed_vifs[eth.to_sym][:ref])
                # Recreate
                mac = option[:mac] || ''
                eth_n = eth.to_s[-1, 1]
                next_device = env[:xc].call("VM.get_allowed_VIF_devices", env[:session], myvm)['Value']
                # TODO: Make error definition in errors.rb
                raise "FATAL: invalid network device (#{eth})" if eth_n.to_i != next_device[0].to_i

                vif_record = {
                  'VM' => myvm,
                  'network' => net_ref,
                  'device' => next_device[0].to_s,
                  'MAC' => mac,
                  'MTU' => '1500',
                  'other_config' => {},
                  'qos_algorithm_type' => '',
                  'qos_algorithm_params' => {},
                  'locking_mode' => 'network_default',
                  'ipv4_allowed' => [],
                  'ipv6_allowed' => []
                }

                # Call Xenserver to create VIF
                new_vif = env[:xc].call("VIF.create", env[:session], vif_record)
              else
                # New vif in vagrantfile. Create it
                @logger.info("#{eth}: New interace on network #{net_rec['name_label']}. Creating new VIF")
                mac = option[:mac] || ''

                eth_n = eth.to_s[-1, 1]
                next_device = env[:xc].call("VM.get_allowed_VIF_devices", env[:session], myvm)['Value']
                # TODO: Make error definition in errors.rb
                raise "FATAL: invalid network device (#{eth})" if eth_n.to_i != next_device[0].to_i

                vif_record = {
                  'VM' => myvm,
                  'network' => net_ref,
                  'device' => next_device[0].to_s,
                  'MAC' => mac,
                  'MTU' => '1500',
                  'other_config' => {},
                  'qos_algorithm_type' => '',
                  'qos_algorithm_params' => {},
                  'locking_mode' => 'network_default',
                  'ipv4_allowed' => [],
                  'ipv6_allowed' => []
                }

                # Call Xenserver to create VIF
                new_vif = env[:xc].call("VIF.create", env[:session], vif_record)

              end
            end
          end

          # finally
          @app.call env
        end
      end
    end
  end
end
