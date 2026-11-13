require "./qemu"
require "tmux_repl"

module Alpine
  class Agent
    getter vm : QEMU::VM
    getter interaction : QEMU::Interaction

    def initialize
      iso = File.expand_path(File.join(ENV.fetch("HOME"), "Downloads", "ISOs", "alpine-extended-3.24.2-x86_64.iso"))
  iso_path = File.file?(iso) && File.size(iso) > 0 ? iso : nil
  disks = Dir.exists?("./disks") ? Dir.glob("./disks/*").select { |path| File.file?(path) && File.size(path) > 0 }.sort : [] of String

  if iso_path
    Log.info { "Booting Alpine ISO from #{iso_path}" }
  elsif disks.empty?
    raise "Alpine ISO not found at #{iso}; no non-empty virtual disks found in ./disks"
  else
    Log.info { "Booting Alpine from disk #{disks.first}" }
  end
  @vm = QEMU::VM.new(iso_path: iso_path, name: "Alpine")
      @interaction = QEMU::Interaction.new(@vm)
      @terminated = false
    end

    module Boot
      def boot : Nil
        Log.info { "Waiting for Alpine login prompt" }
        @interaction.wait_for_text("login:", 180.seconds, :third_quadrant)
        Log.info { "Alpine login prompt detected; logging in as root to configure the console font" }
        @interaction.type("root")
        @vm.send_key("ret")
        @interaction.wait_for_text("You can setup the system", 30.seconds, :third_quadrant)
        @interaction.type("sed -i 's|^#\(.*\/community\)$|\1|' /etc/apk/repositories && apk update && apk add font-terminus && setfont /usr/share/consolefonts/ter-132n.psf.gz")
        @vm.send_key("ret")
        Log.info { "Requested font-terminus installation and console font configuration (ter-132n)" }
      end
    end

    module Terminate
      def terminate : Bool
        return true if @terminated
        Log.info { "Terminating Alpine agent" }
        @terminated = @interaction.terminate
        if @terminated
          Log.info { "Alpine agent terminated" }
        else
          Log.error { "Alpine agent reported a shutdown failure" }
        end
        @terminated
      end
    end

    include Boot
    include Terminate
  end

  class REPL
    FOCUS_ENV = "ALPINE_AGENT_REPL_FOCUS"

    def self.focus? : Bool
      value = ENV.fetch(FOCUS_ENV, "true").strip.downcase

      case value
      when "1", "true", "yes", "on"
        true
      when "0", "false", "no", "off"
        false
      else
        raise ArgumentError.new("#{FOCUS_ENV} must be a boolean (true/false, yes/no, on/off, or 1/0); got #{value.inspect}")
      end
    end

    @definition : TmuxREPL::Definition
    @started = false
    @stopped = false

    def initialize(@agent : Agent)
      @definition = TmuxREPL.define("alpine") do |repl|
        repl.on_command("ocr") do |context, arguments|
          raise ArgumentError.new("Usage: ocr") unless arguments.empty?

          result = @agent.interaction.latest_ocr
          if error = result.error
            raise "OCR failed for frame #{result.timestamp}: #{error}"
          end

          if result.text.strip.empty?
            context.puts("(no text recognized)")
          else
            context.write(result.text)
          end
        end
      end
    end

    def run : Nil
      Signal::INT.trap { terminate_on_signal }
      Signal::TERM.trap { terminate_on_signal }

      begin
        focus = self.class.focus?
        @definition.start(focus: focus)
        @started = true

        if focus
          Log.info { "Alpine REPL started in session 'alpine'." }
        else
          Log.info { "Alpine REPL started in session 'alpine'; switch to it with: tmux switch-client -t alpine" }
        end

        @definition.serve
      ensure
        stop
      end
    end

    def stop : Nil
      return if @stopped

      @stopped = true
      @definition.stop if @started
    end

    private def terminate_on_signal : Nil
      begin
        stop
      ensure
        @agent.terminate
        exit
      end
    end
  end

module CLI
    def self.run(arguments : Array(String) = ARGV.dup) : Nil
      args = arguments.dup
      command = args.shift?

      case command
      when "boot"
        Act::Boot.new(args).run
      else
        STDERR.puts "Usage: alpine.agent boot | --help | --version"
        exit 1
      end
    end

    class Act
      getter arguments : Array(String)

      def initialize(@arguments : Array(String) = [] of String)
        validate_arguments
      end

      def validate_arguments
      end

      def run : Nil
        agent = Alpine::Agent.new
        Signal::INT.trap { agent.terminate && exit }
        Signal::TERM.trap { agent.terminate && exit }
        begin
          agent.boot
          perform(agent)
        ensure
          agent.terminate
        end
      end

      protected def perform(agent : Alpine::Agent) : Nil
      end

      class Boot < Act
        def validate_arguments
          unless @arguments.empty?
            STDERR.puts "Usage: alpine.agent boot"
            exit 1
          end
        end

        protected def perform(agent : Alpine::Agent) : Nil
          Log.info { "Alpine agent is running. Starting REPL." }
          Alpine::REPL.new(agent).run
        end
      end
    end
  end


end
