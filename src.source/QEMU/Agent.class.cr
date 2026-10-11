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

include WaitForText

def wait_for_text(
  text : String,
  timeout : Time::Span = 60.seconds,
  region : Symbol = :full_screen
) : XephyrContext::State
  wait_for_text(text, timeout, XephyrContext::ScreenRegion.from_symbol(region))
end
