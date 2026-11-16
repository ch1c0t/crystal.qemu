require "spec"
require "../src/qemu"

class FakeGuestAgentStreamServer
  getter requests = [] of JSON::Any

  def initialize(@path : String)
    @server = UNIXServer.new(@path)
    @status_checks = 0
    @write_handle = 100
    @read_handle = 102
    @stdout_handle = 0_i64
    @stderr_handle = 0_i64
    @stdout_first_sent = false
    @stdout_second_sent = false
    @stderr_sent = false
    @exec_count = 0

    @fiber = spawn do
      socket = @server.accept
      begin
        while line = socket.gets
          request = JSON.parse(line)
          @requests << request
          socket.puts(response_for(request).to_json)
        end
      ensure
        socket.close
      end
    end
  end

  def finish : Nil
    @fiber.join
    @server.close
  end

  private def response_for(request : JSON::Any) : Hash(String, JSON::Any)
    command = request["execute"].as_s
    arguments = request["arguments"]?.try(&.as_h) || {} of String => JSON::Any

    result = case command
    when "guest-sync"
      arguments["id"]
    when "guest-file-open"
      mode = arguments["mode"].as_s
      path = arguments["path"].as_s
      if mode == "w"
        @write_handle += 1
        JSON::Any.new(@write_handle)
      else
        @read_handle += 1
        if path.ends_with?(".stdout")
          @stdout_handle = @read_handle.to_i64
        else
          @stderr_handle = @read_handle.to_i64
        end
        JSON::Any.new(@read_handle)
      end
    when "guest-file-close", "guest-file-seek"
      if command == "guest-file-seek"
        JSON::Any.new({
          "position" => JSON::Any.new(0),
          "eof"      => JSON::Any.new(false),
        })
      else
        JSON::Any.new(nil)
      end
    when "guest-file-read"
      read_file(arguments["handle"].as_i64)
    when "guest-exec"
      @exec_count += 1
      JSON::Any.new({"pid" => JSON::Any.new(@exec_count == 1 ? 42 : 43)})
    when "guest-exec-status"
      status(arguments["pid"].as_i64)
    else
      raise "Unexpected fake QGA command: #{command}"
    end

    {"return" => result}
  end

  private def read_file(handle : Int64) : JSON::Any
    chunk = if handle == @stdout_handle
              if @status_checks == 0 && !@stdout_first_sent
                @stdout_first_sent = true
                "first "
              elsif @status_checks == 1 && !@stdout_second_sent
                @stdout_second_sent = true
                "second\n"
              else
                ""
              end
            elsif handle == @stderr_handle && !@stderr_sent
              @stderr_sent = true
              "warning\n"
            else
              ""
            end

    JSON::Any.new({
      "count"   => JSON::Any.new(chunk.bytesize),
      "buf-b64" => JSON::Any.new(Base64.strict_encode(chunk)),
      "eof"     => JSON::Any.new(chunk.empty?),
    })
  end

  private def status(pid : Int64) : JSON::Any
    if pid == 42
      @status_checks += 1
      if @status_checks == 1
        JSON::Any.new({"exited" => JSON::Any.new(false)})
      else
        JSON::Any.new({
          "exited"  => JSON::Any.new(true),
          "exitcode" => JSON::Any.new(7),
        })
      end
    else
      JSON::Any.new({
        "exited"  => JSON::Any.new(true),
        "exitcode" => JSON::Any.new(0),
      })
    end
  end
end

describe QEMU::GuestAgent do
  it "streams stdout and stderr before process exit and returns the final exit code" do
    socket_path = File.join(Dir.tempdir, "qga-stream-#{Process.pid}-#{Random.rand(1_000_000)}.sock")
    server = FakeGuestAgentStreamServer.new(socket_path)
    chunks = [] of Tuple(Symbol, String)

    begin
      result = QEMU::GuestAgent.new(socket_path).execute_streaming(
        "printf 'first second'; printf 'warning' >&2",
        2.seconds,
        5.milliseconds
      ) do |stream, chunk|
        chunks << {stream, chunk}
      end

      result.exit_code.should eq(7)
      result.stdout.should eq("first second\n")
      result.stderr.should eq("warning\n")
      chunks.should contain({:stdout, "first "})
      chunks.should contain({:stdout, "second\n"})
      chunks.should contain({:stderr, "warning\n"})

      requests = server.requests.map { |item| item["execute"].as_s }
      first_read = requests.index("guest-file-read")
      first_status = requests.index("guest-exec-status")
      first_read.should_not be_nil
      first_status.should_not be_nil
      first_read.not_nil!.should be < first_status.not_nil!
      requests.count("guest-file-close").should eq(4)
      requests.count("guest-exec").should eq(2)
    ensure
      server.finish
      File.delete(socket_path) if File.exists?(socket_path)
    end
  end

  it "runs without requiring an output callback" do
    socket_path = File.join(Dir.tempdir, "qga-stream-no-callback-#{Process.pid}-#{Random.rand(1_000_000)}.sock")
    server = FakeGuestAgentStreamServer.new(socket_path)

    begin
      result = QEMU::GuestAgent.new(socket_path).execute_streaming(
        "printf 'output'",
        2.seconds,
        5.milliseconds
      )

      result.exit_code.should eq(7)
      result.stdout.should eq("first second\n")
      result.stderr.should eq("warning\n")
    ensure
      server.finish
      File.delete(socket_path) if File.exists?(socket_path)
    end
  end

  it "rejects a non-positive polling interval before connecting" do
    expect_raises(ArgumentError, "Streaming poll interval must be positive") do
      QEMU::GuestAgent.new("/missing-qga.sock").execute_streaming("true", 1.second, 0.milliseconds)
    end
  end
end
