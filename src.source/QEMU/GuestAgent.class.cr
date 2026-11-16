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

# Execute a guest command while forwarding stdout and stderr as soon as they
# become available. The guest agent's guest-exec-status only exposes captured
# output after process exit, so streaming uses guest-file-read on temporary
# files in the guest's /tmp directory instead.
def execute_streaming(
  command : String,
  timeout : Time::Span = 30.seconds,
  poll_interval : Time::Span = 100.milliseconds
) : CommandResult
  execute_streaming(command, timeout, poll_interval) do |_stream, _chunk|
  end
end

def execute_streaming(
  command : String,
  timeout : Time::Span = 30.seconds,
  poll_interval : Time::Span = 100.milliseconds,
  &on_output : Symbol, String ->
) : CommandResult
  raise ArgumentError.new("Streaming poll interval must be positive") if poll_interval <= 0.seconds

  run_id = "#{Process.pid}-#{Random.rand(1_i64..Int64::MAX)}"
  stdout_path = "/tmp/qemu-guest-agent-#{run_id}.stdout"
  stderr_path = "/tmp/qemu-guest-agent-#{run_id}.stderr"

  begin
    UNIXSocket.open(@socket_path) do |socket|
      stdout_handle = nil.as(Int64?)
      stderr_handle = nil.as(Int64?)
      command_started = false
      command_exited = false

      begin
        synchronize(socket)
        create_stream_file(socket, stdout_path)
        create_stream_file(socket, stderr_path)
        stdout_handle = open_stream_file(socket, stdout_path)
        stderr_handle = open_stream_file(socket, stderr_path)

        pid = start_command(socket, streaming_command(command, stdout_path, stderr_path), false)
        command_started = true

        result = wait_for_streaming_command(
          socket,
          pid,
          timeout,
          poll_interval,
          stdout_handle,
          stderr_handle,
          &on_output
        )
        command_exited = true
        result
      ensure
        close_stream_file(socket, stdout_handle) if stdout_handle
        close_stream_file(socket, stderr_handle) if stderr_handle

        # On timeout the guest process may still be running. Preserve its
        # output files so the caller can inspect them instead of unlinking
        # files that the process may still be writing.
        cleanup_stream_files(socket, stdout_path, stderr_path) if command_exited || !command_started
      end
    end
  rescue error : Interaction::TimeoutError
    raise Interaction::TimeoutError.new(
      "#{error.message}; guest output was retained at #{stdout_path} and #{stderr_path}"
    )
  rescue error : IO::Error
    raise "Cannot connect to QEMU Guest Agent at #{@socket_path}: #{error.message}"
  end
end

private def synchronize(socket : UNIXSocket) : Nil
  id = Random.rand(1..Int32::MAX)
  response = request(socket, "guest-sync", {"id" => JSON::Any.new(id)})
  raise "QEMU Guest Agent synchronization failed" unless response.as_i == id
end

private def start_command(
  socket : UNIXSocket,
  command : String,
  capture_output : Bool = true
) : Int64
  arguments = {
    "path" => JSON::Any.new("/bin/sh"),
    "arg" => JSON::Any.new(["-lc", command].map { |arg| JSON::Any.new(arg) }),
    "capture-output" => JSON::Any.new(capture_output),
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

private def wait_for_streaming_command(
  socket : UNIXSocket,
  pid : Int64,
  timeout : Time::Span,
  poll_interval : Time::Span,
  stdout_handle : Int64,
  stderr_handle : Int64,
  &on_output : Symbol, String ->
) : CommandResult
  deadline = Time.instant + timeout
  stdout_buffer = IO::Memory.new
  stderr_buffer = IO::Memory.new

  loop do
    read_available_output(socket, stdout_handle, :stdout, stdout_buffer, &on_output)
    read_available_output(socket, stderr_handle, :stderr, stderr_buffer, &on_output)

    data = request(socket, "guest-exec-status", {"pid" => JSON::Any.new(pid)}).as_h
    if data["exited"].as_bool
      # Drain bytes written between the preceding read and process exit.
      read_available_output(socket, stdout_handle, :stdout, stdout_buffer, &on_output)
      read_available_output(socket, stderr_handle, :stderr, stderr_buffer, &on_output)

      signal = data["signal"]?.try(&.as_i) || 0
      exit_code = data["exitcode"]?.try(&.as_i) || (128 + signal)
      return CommandResult.new(exit_code.to_i32, stdout_buffer.to_s, stderr_buffer.to_s)
    end

    raise Interaction::TimeoutError.new("Guest command timed out after #{timeout}") if Time.instant >= deadline
    sleep poll_interval
  end
end

private def create_stream_file(socket : UNIXSocket, path : String) : Nil
  handle = open_stream_file(socket, path, "w")
  request(socket, "guest-file-close", {"handle" => JSON::Any.new(handle)})
  nil
end

private def open_stream_file(socket : UNIXSocket, path : String, mode : String = "r") : Int64
  arguments = {
    "path" => JSON::Any.new(path),
    "mode" => JSON::Any.new(mode),
  }
  request(socket, "guest-file-open", arguments).as_i64
end

private def close_stream_file(socket : UNIXSocket, handle : Int64) : Nil
  request(socket, "guest-file-close", {"handle" => JSON::Any.new(handle)})
  nil
rescue
  nil
end

private def read_available_output(
  socket : UNIXSocket,
  handle : Int64,
  stream : Symbol,
  buffer : IO::Memory,
  &on_output : Symbol, String ->
) : Nil
  loop do
    # fseek(offset: 0, whence: SEEK_CUR) clears the EOF indicator so a file
    # that grows after a previous read-at-EOF can be read again.
    request(
      socket,
      "guest-file-seek",
      {
        "handle" => JSON::Any.new(handle),
        "offset" => JSON::Any.new(0),
        "whence" => JSON::Any.new(1),
      }
    )

    data = request(
      socket,
      "guest-file-read",
      {
        "handle" => JSON::Any.new(handle),
        "count" => JSON::Any.new(16 * 1024),
      }
    ).as_h
    break if data["count"].as_i == 0

    chunk = decode_output(data, "buf-b64")
    buffer.write(chunk.to_slice)
    yield stream, chunk unless chunk.empty?
  end
end

private def streaming_command(command : String, stdout_path : String, stderr_path : String) : String
  "( #{command}\n) > '#{stdout_path}' 2> '#{stderr_path}'"
end

private def cleanup_stream_files(socket : UNIXSocket, stdout_path : String, stderr_path : String) : Nil
  command = "rm -f '#{stdout_path}' '#{stderr_path}'"
  pid = start_command(socket, command, false)
  wait_for_command(socket, pid, 5.seconds)
  nil
rescue
  nil
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
