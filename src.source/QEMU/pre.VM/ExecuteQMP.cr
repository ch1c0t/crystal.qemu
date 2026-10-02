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
