require "process"
require "socket"
require "file_utils"
require "json"

module QEMU

  class VM
    property name : String? 
    property memory : String
    property cpus : Int32
    property iso_path : String
    property shared_path : String
    property monitor_path : String 
    
    getter display : String? = nil
    
    def initialize(
      @name = nil, 
      @memory = "6G", 
      @cpus = 2, 
      @iso_path = "alpine.iso", 
      @shared_path = "#{ENV["HOME"]}/shared/", 
      @monitor_path = "/tmp/qmp-guest-#{Random.rand(100000)}.sock",
      auto_start : Bool = true
    )
      if auto_start
        unless start
          raise "Failed to initialize and start QEMU guest"
        end
      end
    end
    
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
        "-cdrom", @iso_path,
        "-qmp", "unix:#{@monitor_path},server,nowait"
      ])
    
      cmd_parts.join(" ")
    end
    
    def start : Bool
      return false if @display
    
      File.delete(@monitor_path) if File.exists?(@monitor_path)
    
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
    
    def running? : Bool
      !@display.nil?
    end
    
    def stop : Bool
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
    
          payload = {"execute" => execute_command}
          if args = arguments
            payload["arguments"] = args.transform_values { |v| v.as(JSON::Any) }
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
  end
end