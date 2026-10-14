require "./qemu"

module GRML

  class Agent
    module Boot
      def boot : Nil
        Log.info { "Waiting for GRML boot prompt" }
        @interaction.wait_for_text("Press ENTER to boot", region: :bottom_tenth)
        Log.info { "Sending Return to GRML boot prompt" }
        @vm.send_key("ret")
      
        Log.info { "Waiting for GRML key prompt" }
        @interaction.wait_for_text("Press a key", region: :bottom_tenth)
        Log.info { "Sending Return to GRML key prompt" }
        @vm.send_key("ret")
      
        Log.info { "Waiting for GRML shell prompt" }
        @interaction.wait_for_text("root@grml", 180.seconds, :bottom_tenth)
        Log.info { "GRML command line ready; checking QEMU Guest Agent" }
      
        result = @interaction.execute("printf 'qemu-guest-agent-ok\\n'")
        unless result.success? && result.stdout.strip == "qemu-guest-agent-ok"
          raise "QEMU Guest Agent test failed (exit=#{result.exit_code}, stdout=#{result.stdout.inspect}, stderr=#{result.stderr.inspect})"
        end
      
        Log.info { "QEMU Guest Agent is operational" }
        Log.info { "Verifying GRML shared directory" }
        verify_shared_directory
        Log.info { "GRML shared directory is operational" }
        Log.info { "Press Ctrl-C to terminate the VM." }
      end
    end
  
    module CreateAlpineImage
      def create_alpine_image(iso_path : String? = nil) : Nil
        iso = QEMU::ISOResolver.resolve("alpine", iso_path)
        Log.info { "Found Alpine Linux ISO: #{iso}" }
        raise "Alpine image creation workflow is not implemented yet"
      end
    end
  
    module Terminate
      def terminate : Bool
        return true if @terminated
      
        Log.info { "Terminating GRML agent" }
        @terminated = @interaction.terminate
        if @terminated
          Log.info { "GRML agent terminated" }
        else
          Log.error { "GRML agent reported a shutdown failure" }
        end
        @terminated
      end
    end
  
    module VerifySharedDirectory
      def verify_shared_directory : Nil
        token = Random.rand(1_i64..Int64::MAX).to_s
        host_file = File.join(@vm.shared_path, ".qemu-host-check-#{token}")
        guest_host_file = "/mnt/shared/.qemu-host-check-#{token}"
        guest_file = "/mnt/shared/.qemu-guest-check-#{token}"
        File.write(host_file, token)
      
        begin
          verify_guest_mount
          verify_guest_read(guest_host_file, token)
          verify_guest_write(guest_file, token)
          unless File.read(File.join(@vm.shared_path, File.basename(guest_file))) == token
            raise "Guest-created shared file is not visible to the host"
          end
        ensure
          @interaction.execute("unlink #{guest_host_file}")
          @interaction.execute("unlink #{guest_file}")
          File.delete(host_file) if File.exists?(host_file)
        end
      end
      
      private def verify_guest_mount : Nil
        command = "mkdir -p /mnt/shared && (mountpoint -q /mnt/shared || " +
          "mount -t 9p -o trans=virtio,version=9p2000.L shared0 /mnt/shared)"
        result = @interaction.execute(command)
        raise "Could not mount QEMU shared directory at /mnt/shared" unless result.success?
      end
      
      private def verify_guest_read(path : String, expected : String) : Nil
        result = @interaction.execute("cat #{path}")
        unless result.success? && result.stdout.strip == expected
          raise "GRML guest cannot read files from the shared directory"
        end
      end
      
      private def verify_guest_write(path : String, token : String) : Nil
        result = @interaction.execute("printf '%s' #{token} > #{path}")
        raise "GRML guest cannot write to the shared directory" unless result.success?
      end
    end
  
    getter vm : QEMU::VM
    getter interaction : QEMU::Agent
    
    def initialize(iso_path : String? = nil)
      resolved_iso = QEMU::ISOResolver.resolve("grml", iso_path)
      @vm = QEMU::VM.new(iso_path: resolved_iso)
      @interaction = QEMU::Agent.new(@vm)
      @terminated = false
    end
    
    include Boot
    include VerifySharedDirectory
    include CreateAlpineImage
    include Terminate
  end

  module CLI
    def self.run(arguments : Array(String) = ARGV.dup) : Nil
      args = arguments.dup
      command = args.shift?
    
      case command
      when "boot"
        Act::Boot.new(args).run
      when "create_alpine_image"
        Act::CreateAlpineImage.new(args).run
      else
        STDERR.puts "Usage: grml.agent boot [--iso PATH] | create_alpine_image [alpine_iso_path]"
        exit 1
      end
    end
  
    class Act
      getter arguments : Array(String)
      getter boot_iso_path : String?
      
      def initialize(@arguments : Array(String) = [] of String)
        @boot_iso_path = nil
        validate_arguments
      end
      
      def validate_arguments
      end
      
      def run : Nil
        agent = GRML::Agent.new(@boot_iso_path)
        Signal::INT.trap { agent.terminate && exit }
        Signal::TERM.trap { agent.terminate && exit }
        begin
          agent.boot
          perform(agent)
        ensure
          agent.terminate
        end
      end
      
      protected def perform(agent : GRML::Agent) : Nil
      end
    
      class Boot < Act
        def validate_arguments
          if @arguments.size == 2 && @arguments[0] == "--iso"
            @boot_iso_path = @arguments[1]
          else
            unless @arguments.empty?
              STDERR.puts "Usage: grml.agent boot [--iso PATH]"
              exit 1
            end
          end
        end
        
        protected def perform(agent : GRML::Agent) : Nil
          Log.info { "GRML agent is running. Press Ctrl-C to terminate the VM." }
          sleep
        end
      end
    
      class CreateAlpineImage < Act
        @iso_path : String?
        
        def validate_arguments
          if @arguments.size > 1
            STDERR.puts "Usage: grml.agent create_alpine_image [alpine_iso_path]"
            exit 1
          end
        
          @iso_path = @arguments.first?
        end
        
        protected def perform(agent : GRML::Agent) : Nil
          agent.create_alpine_image(@iso_path)
        end
      end
    end
  end
end