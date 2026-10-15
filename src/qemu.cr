require "base64"
require "process"
require "socket"
require "file_utils"
require "json"
require "mutex"
require "xephyr_context"
require "global-amqp_channel"

module QEMU

  struct CommandResult
    getter exit_code : Int32
    getter stdout : String
    getter stderr : String
    
    def initialize(@exit_code : Int32, @stdout : String, @stderr : String)
    end
    
    def success? : Bool
      @exit_code == 0
    end
  end

  class GuestAgent
    getter socket_path : String
    
    def initialize(@socket_path : String)
    end
    
    def execute(command : String, timeout : Time::Span = 30.seconds) : CommandResult
      UNIXSocket.open(@socket_path) do |socket|
        synchronize(socket)
        pid = start_command(socket, command)
        wait_for_command(socket, pid, timeout)
      end
    rescue error : IO::Error
      raise "Cannot connect to QEMU Guest Agent at #{@socket_path}: #{error.message}"
    end
    
    private def synchronize(socket : UNIXSocket) : Nil
      id = Random.rand(1..Int32::MAX)
      response = request(socket, "guest-sync", {"id" => JSON::Any.new(id)})
      raise "QEMU Guest Agent synchronization failed" unless response.as_i == id
    end
    
    private def start_command(socket : UNIXSocket, command : String) : Int64
      arguments = {
        "path" => JSON::Any.new("/bin/sh"),
        "arg" => JSON::Any.new(["-lc", command].map { |arg| JSON::Any.new(arg) }),
        "capture-output" => JSON::Any.new(true),
      }
      request(socket, "guest-exec", arguments).as_h["pid"].as_i64
    end
    
    private def wait_for_command(
      socket : UNIXSocket,
      pid : Int64,
      timeout : Time::Span
    ) : CommandResult
      deadline = Time.instant + timeout
      loop do
        data = request(socket, "guest-exec-status", {"pid" => JSON::Any.new(pid)}).as_h
        return command_result(data) if data["exited"].as_bool
        raise Interaction::TimeoutError.new("Guest command timed out after #{timeout}") if Time.instant >= deadline
        sleep 100.milliseconds
      end
    end
    
    private def command_result(data : Hash(String, JSON::Any)) : CommandResult
      signal = data["signal"]?.try(&.as_i) || 0
      exit_code = data["exitcode"]?.try(&.as_i) || (128 + signal)
      CommandResult.new(
        exit_code.to_i32,
        decode_output(data, "out-data"),
        decode_output(data, "err-data")
      )
    end
    
    private def decode_output(data : Hash(String, JSON::Any), key : String) : String
      encoded = data[key]?.try(&.as_s)
      encoded ? Base64.decode_string(encoded) : ""
    end
    
    private def request(
      socket : UNIXSocket,
      command : String,
      arguments : Hash(String, JSON::Any)? = nil
    ) : JSON::Any
      payload = {"execute" => JSON::Any.new(command)}
      payload["arguments"] = JSON::Any.new(arguments) if arguments
      socket.puts(payload.to_json)
      line = socket.gets || raise "QEMU Guest Agent disconnected"
      response = JSON.parse(line)
      data = response.as_h
      raise "QEMU Guest Agent error: #{data["error"]}" if data["error"]?
      data["return"]? || raise "QEMU Guest Agent response has no return value"
    end
  end

  class ISOResolver
    DEFAULT_DIRECTORY = "./cdrom"
    
    def self.resolve(distribution : String, path : String? = nil) : String
      return validate(path) if path
      configured_directory = ENV["QEMU_ISO_DIR"]?
      default_directory = File.exists?(DEFAULT_DIRECTORY) ? DEFAULT_DIRECTORY : File.join(ENV.fetch("HOME"), "Downloads", "ISOs")
      directory = File.expand_path(configured_directory || default_directory)
      raise "ISO directory does not exist: #{directory}" unless Dir.exists?(directory)
      pattern = /(?i)#{Regex.escape(distribution)}.*\.iso\z/
      candidates = Dir.glob(File.join(directory, "*")).select do |candidate|
        File.file?(candidate) && File.basename(candidate).matches?(pattern) && File.size(candidate) > 0
      end
      case candidates.size
      when 1
        validate(candidates.first)
      when 0
        raise "No #{distribution} ISO found in #{directory}; pass an ISO path explicitly"
      else
        names = candidates.map { |candidate| File.basename(candidate) }.join(", ")
        Log.debug {"Multiple #{distribution} ISOs found in #{directory}: #{names}"}
        validate(candidates.first)
      end
    end
    
    private def self.validate(path : String) : String
      absolute_path = File.expand_path(path)
      unless File.file?(absolute_path) && File.extname(absolute_path).downcase == ".iso" && File.size(absolute_path) > 0
        raise "Not a non-empty ISO file: #{absolute_path}"
      end
      File.open(absolute_path) { }
      absolute_path
    rescue error : File::Error
      raise "Cannot read ISO #{path}: #{error.message}"
    end
  end

  class Interaction
    module Execute
      def execute(command : String, timeout : Time::Span = 30.seconds) : CommandResult
        GuestAgent.new(@vm.guest_agent_path).execute(command, timeout)
      end
    end
  
    module Terminate
      def terminate : Bool
        result = false
      
        begin
          @context.stop
        ensure
          begin
            @context_process.terminate
          ensure
            result = @vm.terminate
          end
        end
      
        result
      end
    end
  
    module Type
      # Type text into the guest's active window using xdotool.
      # delay is the number of milliseconds between simulated keystrokes.
      def type(text : String, delay : Int32 = 12) : Nil
        raise ArgumentError.new("Typing delay must be non-negative") if delay < 0
        return if text.empty?
      
        display = @vm.display || raise "QEMU VM did not provide a display"
        stderr = IO::Memory.new
        result = Process.run(
          "xdotool",
          ["type", "--clearmodifiers", "--delay", delay.to_s, "--", text],
          env: {"DISPLAY" => display},
          error: stderr
        )
      
        unless result.success?
          raise "xdotool type failed (exit=#{result.exit_code}): #{stderr}"
        end
      end
    end
  
    module WaitForText
      def wait_for_text(
        text : String,
        timeout : Time::Span = 60.seconds,
        region : Symbol = :full_screen
      ) : XephyrContext::State
        wait_for_text(text, timeout, XephyrContext::ScreenRegion.from_symbol(region))
      end
      
      def wait_for_text(
        text : String,
        timeout : Time::Span = 60.seconds,
        region : XephyrContext::ScreenRegion = XephyrContext::ScreenRegion.full_screen,
      ) : XephyrContext::State
        @context.wait_until(text, timeout, region)
      rescue error : RuntimeError
        raise error unless error.message == "Timed out waiting for #{text.inspect}"
        raise TimeoutError.new(error.message || "Timed out waiting for text")
      end
    end
  
    class TimeoutError < Exception
    end
    
    getter vm : VM
    getter context : XephyrContext
    getter context_process : ProcessSupervisor
    
    def initialize(@vm : VM)
      display = @vm.display
      raise "QEMU VM did not provide a display" if display.nil?
    
      @context_process = ProcessSupervisor.new(
        "xephyr.context",
        {
          "DISPLAY_TARGET" => display,
          "XEPHYR_LOG_LEVEL" => ENV.fetch("XEPHYR_LOG_LEVEL", "INFO"),
        }
      )
      @context = XephyrContext.new(display, Global.amqp_channel)
    end
    
    include Type
    include WaitForText
    include Execute
    include Terminate
  end

  class ProcessSupervisor
    getter process : Process
    
    def initialize(command : String, env : Hash(String, String))
      @process = Process.new(
        command,
        env: env,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit
      )
    
      at_exit { terminate }
    
    end
    
    def terminate : Nil
      return if @process.terminated?
    
      @process.terminate
      @process.wait
    end
    
    def running? : Bool
      !@process.terminated?
    end
  end

  class VM
    module ExecuteQMP
      def execute_qmp(execute_command : String, arguments : Hash(String, JSON::Any)? = nil) : JSON::Any
        unless running?
          raise "Error: VM is not running."
        end
      
        unless File.exists?(@monitor_path)
          raise "Error: QMP socket file does not exist yet."
        end
      
        begin
          UNIXSocket.open(@monitor_path) do |socket|
            socket.gets # QMP Handshake greeting
      
            handshake_cmd = {"execute" => "qmp_capabilities"}.to_json
            socket.puts(handshake_cmd)
            socket.gets # ACK Response
      
            payload = JSON::Any.new({"execute" => JSON::Any.new(execute_command)}).as_h
            if args = arguments
              payload["arguments"] = JSON::Any.new(args)
            end
      
            socket.puts(payload.to_json)
      
            if response_str = socket.gets
              JSON.parse(response_str)
            else
              raise "Empty response from QMP server"
            end
          end
        rescue e : Exception
          raise "QMP Communication Failure: #{e.message}"
        end
      end
      
      def send_key(key : String) : JSON::Any
        arguments = JSON.parse(%({"keys":[{"type":"qcode","data":#{key.to_json}}]})).as_h
        execute_qmp("send-key", arguments)
      end
    end
  
    module Start
      module BuildQEMUCommand
        def build_qemu_command : String
          cmd_parts = ["qemu-system-x86_64"]
        
          if guest_name = @name
            cmd_parts << "-name" << "'#{guest_name}'"
          end
        
          cmd_parts.concat([
            "-full-screen",
            "-m", @memory,
            "-smp", @cpus.to_s,
            "-enable-kvm",
            "-vga", "virtio",
            *shared_path_options,
            *guest_agent_options,
            *disk_options,
            "-cdrom", @iso_path,
            "-qmp", "unix:#{@monitor_path},server,nowait"
          ])
        
          cmd_parts.join(" ")
        end
        
        def shared_path_options
          [
            "-fsdev", "local,security_model=mapped,id=shared0,path=#{@shared_path}",
            "-device", "virtio-9p-pci,fsdev=shared0,mount_tag=shared0",
          ]
        end
        
        def guest_agent_options
          [
            "-chardev", "socket,path=#{@guest_agent_path},server=on,wait=off,id=qga0",
            "-device", "virtio-serial-pci",
            "-device", "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0",
          ]
        end
        
        def disk_options : Array(String)
          return [] of String unless Dir.exists?("./disks")
        
          Dir.glob("./disks/*").sort.flat_map do |path|
            next [] of String unless File.file?(path)
        
            ["-drive", "file=#{File.expand_path(path)},if=virtio"]
          end
        end
      end
    
      include BuildQEMUCommand
      
      def start : Bool
        return false if @display
      
        verify_shared_directory
      
        File.delete(@monitor_path) if File.exists?(@monitor_path)
        File.delete(@guest_agent_path) if File.exists?(@guest_agent_path)
      
        qemu_cmd = build_qemu_command
        stdout_buffer = IO::Memory.new
        result = Process.run("xephyr-run", [qemu_cmd], shell: false, output: stdout_buffer)
      
        if result.success?
          @display = stdout_buffer.to_s.strip
          true
        else
          false
        end
      end
    end
  
    module Terminate
      def terminate : Bool
        if target_display = @display
          result = Process.run("xephyr-kill", [target_display], shell: false)
          File.delete(@monitor_path) if File.exists?(@monitor_path)
          File.delete(@guest_agent_path) if File.exists?(@guest_agent_path)
      
          if result.success?
            @display = nil
            true
          else
            false
          end
        else
          false
        end
      end
    end
  
    module VerifySharedDirectory
      def verify_shared_directory : Bool
        unless File.exists?(@shared_path)
          raise "QEMU shared directory does not exist: #{@shared_path}"
        end
      
        unless File.directory?(@shared_path)
          raise "QEMU shared path is not a directory: #{@shared_path}"
        end
      
        true
      end
    end
  
    property name : String?
    property memory : String
    property cpus : Int32
    property iso_path : String
    property shared_path : String
    property monitor_path : String
    property guest_agent_path : String
    
    getter display : String? = nil
    
    def initialize(
      @iso_path : String,
      @name = nil,
      @memory = "6G",
      @cpus = 2,
      shared_path : String? = nil,
      @monitor_path = "/tmp/qmp-guest-#{Process.pid}-#{Random.rand(100000)}.sock",
      @guest_agent_path = "/tmp/qga-guest-#{Process.pid}-#{Random.rand(100000)}.sock",
      auto_start : Bool = true
    )
      @shared_path = shared_path || (File.exists?("./shared") ? "./shared/" : "#{ENV["HOME"]}/shared/")
    
      if auto_start
        unless start
          raise "Failed to initialize and start QEMU guest"
        end
      end
    end
    
    include Start
    include VerifySharedDirectory
    include Terminate
    include ExecuteQMP
    
    def running? : Bool
      !@display.nil?
    end
  end
end