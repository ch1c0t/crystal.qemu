class TimeoutError < Exception
end

getter vm : VM
getter context : XephyrContext
getter context_process : ProcessSupervisor

def initialize(@vm : VM = VM.new)
  display = @vm.display
  raise "QEMU VM did not provide a display" if display.nil?

  @context_process = ProcessSupervisor.new(
    "xephyr.context",
    {"DISPLAY_TARGET" => display}
  )
  @context = XephyrContext.new(display, Global.amqp_channel)
end

def wait_for_text(text : String, timeout : Time::Span = 30.seconds) : XephyrContext::State
  @context.wait_until(text, timeout)
rescue error : RuntimeError
  raise unless error.message == "Timed out waiting for #{text.inspect}"
  raise TimeoutError.new(error.message || "Timed out waiting for text")
end

def stop : Bool
  @context_process.stop
  @vm.stop
end
