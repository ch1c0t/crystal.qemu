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

def stop : Bool
  result = false

  begin
    @context.stop
  ensure
    begin
      @context_process.stop
    ensure
      result = @vm.stop
    end
  end

  result
end
