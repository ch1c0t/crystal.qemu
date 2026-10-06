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

def wait_for_text(text : String, timeout : Time::Span = 30.seconds) : Bool
  @context.wait_until(text, timeout)
  true
rescue RuntimeError
  false
end

def stop : Bool
  @context_process.stop
  @vm.stop
end
