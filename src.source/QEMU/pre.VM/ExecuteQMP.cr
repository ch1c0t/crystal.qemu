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
