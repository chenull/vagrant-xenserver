require "log4r"
require "xmlrpc/client"
require "vagrant-xenserver/util/uploader"
require "rexml/document"
require "json"
require "digest/md5"

module VagrantPlugins
  module XenServer
    module Action
      class UploadVHD

        @@lock = Mutex.new

        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant::xenserver::actions::upload_vhd")
        end

        def get_vhd_size(box_vhd_file)
          # Find out virtual size of the VHD
          disk_info={}
          begin
            begin
              disk_info=JSON.parse(IO.popen(["qemu-img", "info",box_vhd_file,"--output=json"]).read)
            rescue JSON::ParserError
              size=`qemu-img info #{box_vhd_file} | grep "virtual size" | cut "-d(" -f2 | cut "-d " -f1`
              disk_info['virtual-size']=size.strip
            end
          rescue
            @logger.error("Error getting virtual size of VHD: #{box_vhd_file}")
            raise Errors::QemuImgError
          end
          return disk_info['virtual-size']
        end

        def call(env)
          box_vhd_file = env[:machine].box.directory.join('box.vhd').to_s

          hostname = env[:machine].provider_config.xs_host
          session = env[:session]

          @logger.info("box name=" + env[:machine].box.name.to_s)
          @logger.info("box version=" + env[:machine].box.version.to_s)

          md5=File.open(box_vhd_file) do |fh| Digest::MD5.hexdigest(fh.read(1024*1024)) end

          @logger.info("md5=#{md5}")

          # Find out if it has already been uploaded
          @@lock.synchronize do

            vdis = env[:xc].call("VDI.get_all_records", env[:session])['Value']

            vdi_tag = "vagrant:" + env[:machine].box.name.to_s + "/" + md5

            vdi_ref_rec = vdis.find { |reference,record|
              @logger.info(record['tags'].to_s)
              record['tags'].include?(vdi_tag)
            }

            if not vdi_ref_rec
              virtual_size = get_vhd_size(box_vhd_file)
              @logger.info("virtual_size=#{virtual_size}")
              pool=env[:xc].call("pool.get_all",env[:session])['Value'][0]
              default_sr=env[:xc].call("pool.get_default_SR",env[:session],pool)['Value']
              @logger.info("default_SR="+default_sr)

              # Verify the default SR is valid:
              if env[:xc].call("SR.get_uuid",env[:session],default_sr)['Status'] != "Success"
                raise Errors::NoDefaultSR
              end

              vdi_record = {
                'name_label' => 'Vagrant disk',
                'name_description' => 'Base disk uploaded for the vagrant box '+env[:machine].box.name.to_s+' v'+env[:machine].box.version.to_s,
                'SR' => default_sr,
                'virtual_size' => "#{virtual_size}",
                'type' => 'user',
                'sharable' => false,
                'read_only' => false,
                'other_config' => {},
                'xenstore_data' => {},
                'sm_config' => {},
                'tags' => [] }

              vdi_result=env[:xc].call("VDI.create",env[:session],vdi_record)['Value']

              @logger.info("created VDI: " + vdi_result.to_s)
              vdi_uuid = env[:xc].call("VDI.get_uuid",env[:session],vdi_result)['Value']
              @logger.info("uuid: "+vdi_uuid)

              # Create a task to so we can get the result of the upload
              task_result = env[:xc].call("task.create", env[:session], "vagrant-vhd-upload",
                                          "Task to track progress of the XVA upload from vagrant")

              if task_result["Status"] != "Success"
                raise Errors::APIError
              end

              task = task_result["Value"]

              url = "https://#{hostname}/import_raw_vdi?session_id=#{session}&task_id=#{task}&vdi=#{vdi_result}&format=vhd"

              uploader_options = {}
              uploader_options[:ui] = env[:ui]
              uploader_options[:insecure] = true

              uploader = MyUtil::Uploader.new(box_vhd_file, url, uploader_options)

              begin
                uploader.upload!
              rescue Errors::UploaderInterrupted
                env[:ui].info(I18n.t("vagrant.xenserver.action.upload_xva.interrupted"))
                raise
              end

              task_status = ""

              begin
                sleep(0.2)
                task_status_result = env[:xc].call("task.get_status",env[:session],task)
                if task_status_result["Status"] != "Success"
                  raise Errors::APIError
                end
                task_status = task_status_result["Value"]
              end while task_status == "pending"

              @logger.info("task_status="+task_status)

              if task_status != "success"
                raise Errors::APIError
              end

              task_result_result = env[:xc].call("task.get_result",env[:session],task)
              if task_result_result["Status"] != "Success"
                raise Errors::APIError
              end

              task_result = task_result_result["Value"]

              doc = REXML::Document.new(task_result)

              doc.elements.each('value/array/data/value') do |ele|
                vdi = ele.text
              end

              @logger.info("task_result=" + task_result)

              tag_result=env[:xc].call("VDI.add_tags",env[:session],vdi_result,vdi_tag)
              @logger.info("task_result=" + tag_result.to_s)

              env[:box_vdi] = vdi_result
            else
              (reference,record) = vdi_ref_rec
              env[:box_vdi] = reference
              @logger.info("box_vdi="+reference)

            end
          end

          @app.call(env)
        end
      end
    end
  end
end
