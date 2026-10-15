# Type text into the guest's active window using xdotool.
# delay is the number of milliseconds between simulated keystrokes.
def type(text : String, delay : Int32 = 12) : Nil
  raise ArgumentError.new("Typing delay must be non-negative") if delay < 0
  return if text.empty?

  display = @vm.display || raise "QEMU VM did not provide a display"
  stderr = IO::Memory.new
  result = Process.run(
    "xdotool",
    ["type", "--clearmodifiers", "--delay", delay.to_s, "--", text],
    env: {"DISPLAY" => display},
    error: stderr
  )

  unless result.success?
    raise "xdotool type failed (exit=#{result.exit_code}): #{stderr}"
  end
end
