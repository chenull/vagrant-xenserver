require "log4r"
require "set"
require "tempfile"

module VagrantPlugins
  module XenServer
    module Action
      # This action modify /etc/resolver.conf
      class ConfigureResolver

        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant::xenserver::actions::configure_resolver")
        end

        def call(env)
          # Accumulate the DNS configured in env[:vifs][:dns]
          dhcp_enabled = false
          dns = Set.new
          env[:vifs].each do |vif, option|

            # Skip if any interface is using DHCP
            # Assume resolver is configured via DHCP
            if !option[:proto].nil?
              if option[:proto] == "dhcp"
                dhcp_enabled = true
                break
              end
            end

            if !option[:dns].nil?
              option[:dns].split(/[\s,;]+/).each do |ns|
                dns.add(ns)
              end
            end
          end

          if not dhcp_enabled
            dns_str = dns.to_a.join(", ")
            @logger.info("Configuring DNS [#{dns_str}]")
            env[:ui].info I18n.t("vagrant_xenserver.info.configure_resolver",
              dns: dns_str)

            env[:machine].guest.capability(
              :configure_resolver, dns)
          end

          # finally
          @app.call env
        end
      end
    end
  end
end
