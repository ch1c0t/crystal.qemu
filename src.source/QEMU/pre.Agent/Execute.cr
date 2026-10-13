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
