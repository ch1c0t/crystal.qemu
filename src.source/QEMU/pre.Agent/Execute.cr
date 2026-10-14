def execute(command : String, timeout : Time::Span = 30.seconds) : CommandResult
  UNIXSocket.open(@vm.guest_agent_path) do |socket|
    synchronize_guest_agent(socket)

    arguments = {
      "path" => JSON::Any.new("/bin/sh"),
      "arg" => JSON::Any.new(["-lc", command].map { |arg| JSON::Any.new(arg) }),
      "capture-output" => JSON::Any.new(true),
    }
    pid = guest_agent_request(socket, "guest-exec", arguments).as_h["pid"].as_i
    wait_for_command(socket, pid, timeout)
  end
rescue error : IO::Error
  raise "Cannot connect to QEMU Guest Agent at #{@vm.guest_agent_path}: #{error.message}"
end

private def synchronize_guest_agent(socket : UNIXSocket) : Nil
  id = Random.rand(1_i64..Int64::MAX)
  arguments = {"id" => JSON::Any.new(id)}
  response = guest_agent_request(socket, "guest-sync", arguments)
  raise "QEMU Guest Agent synchronization failed" unless response.as_i == id
end

private def wait_for_command(
  socket : UNIXSocket,
  pid : Int64,
  timeout : Time::Span
) : CommandResult
  deadline = Time.instant + timeout
  loop do
    status = guest_agent_request(
      socket,
      "guest-exec-status",
      {"pid" => JSON::Any.new(pid)}
    )
    data = status.as_h
    if data["exited"].as_bool
      signal = data["signal"]?.try(&.as_i) || 0
      exit_code = data["exitcode"]?.try(&.as_i) || (128 + signal)
      return CommandResult.new(
        exit_code.to_i32,
        decode_output(data, "out-data"),
        decode_output(data, "err-data")
      )
    end
    raise TimeoutError.new("Guest command timed out after #{timeout}") if Time.instant >= deadline
    sleep 100.milliseconds
  end
end

private def decode_output(data : Hash(String, JSON::Any), key : String) : String
  encoded = data[key]?.try(&.as_s)
  encoded ? Base64.decode_string(encoded) : ""
end

private def guest_agent_request(
  socket : UNIXSocket,
  command : String,
  arguments : Hash(String, JSON::Any)? = nil
) : JSON::Any
  payload = {"execute" => JSON::Any.new(command)}
  payload["arguments"] = JSON::Any.new(arguments) if arguments
  socket.puts(payload.to_json)
  line = socket.gets || raise "QEMU Guest Agent disconnected"
  line = line.byte_slice(1, line.bytesize - 1) if line.starts_with?("\xff")
  response = JSON.parse(line)
  data = response.as_h
  if error = data["error"]?
    raise "QEMU Guest Agent error: #{error}"
  end
  data["return"]? || raise "QEMU Guest Agent response has no return value"
end
