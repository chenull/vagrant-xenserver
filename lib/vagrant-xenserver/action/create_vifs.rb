require "log4r"
require "xmlrpc/client"

module VagrantPlugins
  module XenServer
    module Action
      class CreateVIFs
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant::xenserver::actions::create_vifs")
        end

        def call(env)
          myvm = env[:machine].id

          # Start from 1. it's the 2nd device (eth1). the 1st (eth0) is HIMN
          vif_count = 1
          env[:vifs].each do |vif, options|
            @logger.info "got an interface:#{vif} on network #{options[:network]}"

            mac = options[:mac] || ''

            next_device = env[:xc].call("VM.get_allowed_VIF_devices",env[:session],myvm)['Value']
            # TODO: Make error definition in errors.rb
            raise "FATAL: invalid network configuration defined in Vagrantfile" if vif_count.to_s != next_device[0]

            vif_record = {
              'VM' => myvm,
              'network' => options[:net_ref],
              'device' => vif_count.to_s,
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
            vif_res = env[:xc].call("VIF.create",env[:session],vif_record)

            # Increment vif_count
            vif_count += 1

            @logger.info("vif_res=" + vif_res.to_s)
          end

          @app.call env
        end
      end
    end
  end
end
