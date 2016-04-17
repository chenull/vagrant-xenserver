require "log4r"
require "xmlrpc/client"

module VagrantPlugins
  module XenServer
    module Action
      class ValidateNetowrk
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant::xenserver::actions::validate_network")
        end

        def call(env)
          myvm = env[:machine].id

          # only find network without :fowarded port, then sort by name label
          vifs = env[:machine].config.vm.networks.reject {
            |k,v| k == :forwarded_port}.sort_by {
              |k,v| v[:network] || ""}

          # this will hold any vifs with no device (ethX)
          vifs_unknown = []

          # create a placeholder hash for all vifs
          # note that eth0 is already used by HIMN, so start with 1
          eth = Hash.new
          vifs.count.times do |x|
            x += 1
            eth["eth#{x}".to_sym] = {}
          end

          # Get All networks without HIMN
          allnetworks = env[:xc].call("network.get_all_records", env[:session])['Value'].reject {
            |ref,net| net['other_config']['is_host_internal_management_network'] }

          # find the network type (public/external or private/single-server)
          # Don't know how to do this in rubyish wae
          allnets = {}
          allnetworks.each do |ref, params|
            allnets[ref] = params
            if params["PIFs"].empty?
              allnets[ref]["network_type"] = "private_network"
            else
              allnets[ref]["network_type"] = "public_network"
            end
          end

          # convert allnets to string for error message
          allnets_str = allnets.map { |k,v| "#{v['name_label']} (#{v['network_type']})"}.join(", ")

          # foreach vifs which has device defined, assign it to `eth` Hash
          vifs.each do |k,v|
            # Check if network name label in configuration matches
            # the network on Xenserver Host
            netrefrec = allnets.find { |ref,net| net['name_label'].upcase == v[:network].upcase }
            (net_ref, net_rec) = netrefrec
            if net_ref.nil?
              raise Errors::InvalidNetwork, network: v[:network], allnetwork: allnets_str, vm: env[:machine].name
            end

            # Assign network UUID/ref
            v[:net_ref] = net_ref

            # Assign network type
            v[:network_type] = net_rec["network_type"]

            # no match, assign a device number (ethX) later
            if v[:device].nil?
              # vifs_unknown will contains vifs without :device defined
              # SORTED BY NETWORK NAME LABEL
              vifs_unknown.push(v)
            else
              if v[:device].start_with?("eth") and eth.include?(v[:device].to_sym)
                eth[v[:device].to_sym] = v
              else
                raise "Configration Error in netowrk `#{v[:network]}' for device name `#{v[:device]}'"
              end
            end
          end


          # Populate `eth' hash from the rest of unconfigured vifs
          vifs_unknown.each do |vif|
            unconfigured_eth = eth.find {|k,v| v.empty?}[0]
            vif[:device] = unconfigured_eth.to_s
            eth[unconfigured_eth.to_sym] = vif
          end

          # Validate network settings:
          #   - if `ip' and dhcp is set, raise error
          #   - ip and netmask must be defined it dhcp is not set
          #   - public_network
          #     - can have gateway
          #   - private_network (internal xenserver host-only network)
          #     - CANNOT have gateway
          #     - if `ip' defined, raise error if dhcp is set
          eth.each do |e, opt|
            raise Errors::InvalidInterface, eth: e, opt: opt[:proto], net: opt[:network],
              message: "No IP address is defined" if opt[:proto] == 'static' and opt[:ip].nil?

            raise Errors::InvalidInterface, eth: e, opt: opt[:proto], net: opt[:network],
              message: "No IP netmask is defined" if opt[:proto] == 'static' and opt[:netmask].nil?

            raise Errors::InvalidInterface, eth: e, opt: opt[:proto], net: opt[:network],
              message: "Cannot assign IP #{opt[:ip]} here" if opt[:proto] == 'dhcp' and !opt[:ip].nil?

            raise Errors::InvalidInterface, eth: e, opt: opt[:network_type], net: opt[:network],
              message: "Cannot assign gateway #{opt[:gateway]} here" if opt[:network_type] == "private_network" and !opt[:gateway].nil?
          end

          # Put eth on global env
          env[:vifs] = eth

          @app.call env
        end
      end
    end
  end
end
