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

            # no match, assign a device number (ethX) later
            if v[:device].nil?
              # vifs_unknown will contains vifs without :device defined
              # SORTED BY NETWORK NAME LABEL
              vifs_unknown.push(v)
            else
              if v[:device].start_with?("eth") and eth.include?(v[:device].to_sym)
                eth[v[:device].to_sym] = v
              else
                raise "Configration Error for network `#{v[:network]}' and device `#{v[:device]}'"
              end
            end
          end

          # Populate `eth' hash from the rest of unconfigured vifs
          vifs_unknown.each do |vif|
            unconfigured_eth = eth.find {|k,v| v.empty?}[0]
            vif[:device] = unconfigured_eth.to_s
            eth[unconfigured_eth.to_sym] = vif
          end

          # Put eth on global env
          env[:vifs] = eth

          @app.call env
        end
      end
    end
  end
end
