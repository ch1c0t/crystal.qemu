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
        Log.info { "GRML command line ready. Press Ctrl-C to terminate the VM." }
      end
    end
  
    module CreateAlpineImage
      module FindAlpineISO
        private def find_alpine_iso(iso_path : String?) : String
          if path = iso_path
            validate_alpine_iso(path)
            return path
          end
        
          directory = File.expand_path(@vm.shared_path)
          raise "Shared directory does not exist: #{directory}" unless Dir.exists?(directory)
        
          candidates = Dir.glob(File.join(directory, "*")).select do |path|
            File.file?(path) && File.basename(path).matches?(/(?i)alpine.*\.iso\z/) && File.size(path) > 0
          end
        
          case candidates.size
          when 0
            raise "No non-empty Alpine Linux ISO found in shared directory: #{directory}"
          when 1
            validate_alpine_iso(candidates.first)
            candidates.first
          else
            raise "Multiple Alpine Linux ISOs found in #{directory}; pass the desired ISO path explicitly"
          end
        end
        
        private def validate_alpine_iso(path : String) : Nil
          unless File.file?(path) &&
                 File.basename(path).matches?(/(?i)alpine.*\.iso\z/) &&
                 File.size(path) > 0
            raise "Not a non-empty Alpine Linux ISO file: #{path}"
          end
        
          File.open(path) { }
        rescue error : File::Error
          raise "Cannot read Alpine Linux ISO #{path}: #{error.message}"
        end
      end
    
      def create_alpine_image(iso_path : String? = nil) : Nil
        iso = find_alpine_iso(iso_path)
        Log.info { "Found Alpine Linux ISO: #{iso}" }
        raise "Alpine image creation workflow is not implemented yet"
      end
      
      include FindAlpineISO
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
  
    getter vm : QEMU::VM
    getter interaction : QEMU::Agent
    
    def initialize(
      iso_path : String = "#{ENV["HOME"]}/Downloads/ISOs/grml-full-2026.09-amd64.iso"
    )
      @vm = QEMU::VM.new(iso_path: iso_path)
      @interaction = QEMU::Agent.new(@vm)
      @terminated = false
    end
    
    include Boot
    include CreateAlpineImage
    include Terminate
  end

  module CLI
  
    class Act
      getter arguments : Array(String)
      
      def initialize(@arguments : Array(String) = ARGV.dup)
      end
      
      def run : Nil
        command, iso_path = parse_arguments
        Log.info { "Starting GRML agent act: #{command}" }
      
        case command
        when "boot"
          Boot.new.run
        when "create_alpine_image"
          CreateAlpineImage.new(iso_path).run
        end
      end
      
      private def parse_arguments : Tuple(String, String?)
        args = @arguments.dup
        command = args.shift?
        unless command == "boot" || command == "create_alpine_image"
          usage_error
        end
      
        iso_path = args.shift?
        if (command == "boot" && iso_path) || !args.empty?
          usage_error
        end
      
        {command.not_nil!, iso_path}
      end
      
      private def usage_error : NoReturn
        STDERR.puts "Usage: grml.agent <boot|create_alpine_image> [alpine_iso_path]"
        exit 1
      end
    
      module WithAgent
        def run : Nil
          agent = GRML::Agent.new
        
          Signal::INT.trap { agent.terminate && exit }
          Signal::TERM.trap { agent.terminate && exit }
        
          begin
            agent.boot
            perform(agent)
          ensure
            agent.terminate
          end
        end
      end
    
      class Boot
        include WithAgent
        
        protected def perform(agent : GRML::Agent) : Nil
          Log.info { "GRML agent is running. Press Ctrl-C to terminate the VM." }
          sleep
        end
      end
    
      class CreateAlpineImage
        include WithAgent
        
        def initialize(@iso_path : String? = nil)
        end
        
        protected def perform(agent : GRML::Agent) : Nil
          agent.create_alpine_image(@iso_path)
        end
      end
    end
  end
end