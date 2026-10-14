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
    raise Agent::TimeoutError.new("Guest command timed out after #{timeout}") if Time.instant >= deadline
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
