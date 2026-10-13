require "process"
require "socket"
require "file_utils"
require "json"
require "base64"
require "mutex"
require "xephyr_context"
require "global-amqp_channel"

module QEMU

  class CommandResult
    getter exit_code : Int32
    getter stdout : String
    getter stderr : String
    
    def initialize(@exit_code : Int32, @stdout : String, @stderr : String)
    end
    
    def success? : Bool
      @exit_code == 0
    end
  end

  class Agent
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
  
    module Execute
      def execute(command : String, timeout : Time::Span = 30.seconds) : CommandResult
        arguments = JSON.parse({
          "path" => "/bin/sh",
          "arg" => ["-lc", command],
          "capture-output" => true,
        }.to_json).as_h
        response = guest_agent_request("guest-exec", arguments)
        pid = response["pid"].as_i

        started_at = Time.instant
        loop do
          status_arguments = JSON.parse({"pid" => pid}.to_json).as_h
          status = guest_agent_request("guest-exec-status", status_arguments)

          if status["exited"].as_bool
            return CommandResult.new(
              status["exitcode"].as_i,
              decode_output(status, "out-data"),
              decode_output(status, "err-data")
            )
          end

          raise TimeoutError.new("Guest command timed out after #{timeout}") if Time.instant - started_at >= timeout
          sleep 50.milliseconds
        end
      end

      private def guest_agent_request(
        command : String,
        arguments : Hash(String, JSON::Any)? = nil
      ) : JSON::Any
        payload = {"execute" => JSON::Any.new(command)}
        payload["arguments"] = JSON::Any.new(arguments) if arguments

        UNIXSocket.open(@vm.guest_agent_path) do |socket|
          socket.puts(payload.to_json)
          response = JSON.parse(socket.gets || raise "Empty response from QEMU guest agent")
          raise "QEMU guest agent error: #{response["error"]}" if response["error"]?
          response["return"]? || JSON::Any.new(nil)
        end
      rescue error : Exception
        raise "QEMU guest agent request failed: #{error.message}"
      end

      private def decode_output(status : JSON::Any, key : String) : String
        encoded = status[key]?.try(&.as_s) || ""
        Base64.decode_string(encoded)
      end
    end

    class TimeoutError < Exception
    end
    
    getter vm : VM
    getter context : XephyrContext
    getter context_process : ProcessSupervisor
    
    def initialize(@vm : VM = VM.new)
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
    
    include WaitForText
    include Execute
    
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
          "-fsdev", "local,security_model=mapped,id=shared0,path=#{@shared_path}",
          "-device", "virtio-9p-pci,fsdev=shared0,mount_tag=shared0",
        "-chardev", "socket,path=#{@guest_agent_path},server=on,wait=off,id=qga0",
        "-device", "virtio-serial-pci,id=virtio-serial-qga",
        "-device", "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0",
          "-cdrom", @iso_path,
          "-qmp", "unix:#{@monitor_path},server,nowait"
        ])
      
        cmd_parts.join(" ")
      end
      
      def start : Bool
        return false if @display
      
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
  
    property name : String? 
    property memory : String
    property cpus : Int32
    property iso_path : String
    property shared_path : String
    property monitor_path : String 
    property guest_agent_path : String
    
    getter display : String? = nil
    
    def initialize(
      @name = nil, 
      @memory = "6G", 
      @cpus = 2, 
      @iso_path = "alpine.iso", 
      @shared_path = "#{ENV["HOME"]}/shared/", 
      @monitor_path = "/tmp/qmp-guest-#{Process.pid}-#{Random.rand(100000)}.sock",
      @guest_agent_path = "/tmp/qga-guest-#{Process.pid}-#{Random.rand(100000)}.sock",
      auto_start : Bool = true
    )
      if auto_start
        unless start
          raise "Failed to initialize and start QEMU guest"
        end
      end
    end
    
    include Start
    include Terminate
    include ExecuteQMP
    
    def running? : Bool
      !@display.nil?
    end
  end
end