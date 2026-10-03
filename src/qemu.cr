require "process"
require "socket"
require "file_utils"
require "json"
require "mutex"
require "xephyr_context"

module QEMU

  class Agent
    getter vm : VM
    getter context : XephyrContext
    getter language : String
    
    @recognizer : XephyrContext::TextRecognizer
    @latest_text = ""
    @text_mutex = Mutex.new
    
    def initialize(@language : String = "eng", @vm : VM = VM.new)
      display = @vm.display
      raise "QEMU VM did not provide a display" if display.nil?
    
      @context = XephyrContext.new(display, Global.amqp_channel)
      @recognizer = XephyrContext::TextRecognizer.new(@language)
    
      @context.each_mutation do |state|
        text = recognize(state)
    
        @text_mutex.synchronize do
          @latest_text = text
        end
      end
    end
    
    def wait_for_text(text : String, timeout : Time::Span = 30.seconds) : Bool
      deadline = Time.monotonic + timeout
    
      loop do
        return true if @text_mutex.synchronize { @latest_text.includes?(text) }
        return false if Time.instant >= deadline
    
        sleep 100.milliseconds
      end
    end
    
    def stop : Bool
      @recognizer.finalize
      @vm.stop
    end
    
    private def recognize(state : XephyrContext::State) : String
      raw_bytes = state.raw_pixels
      expected_size = state.width.to_i64 * state.height.to_i64 * 4
      raise "Unexpected framebuffer size: #{raw_bytes.size}, expected at least #{expected_size}" if raw_bytes.size < expected_size
    
      pixels = Slice(UInt8).new(state.width * state.height)
      offset = 0
    
      state.height.times do |y|
        state.width.times do |x|
          pixel_offset = (y * state.width + x) * 4
          r = raw_bytes[pixel_offset + 2]
          g = raw_bytes[pixel_offset + 1]
          b = raw_bytes[pixel_offset]
    
          pixels[offset] = ((r.to_i * 299 + g.to_i * 587 + b.to_i * 114) // 1000).to_u8
          offset += 1
        end
      end
    
      @recognizer.recognize(pixels, state.width, state.height)
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
    end
  
    module Stop
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
    end
  
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
    
    include Start
    include Stop
    include ExecuteQMP
    
    def running? : Bool
      !@display.nil?
    end
  end
end