class TimeoutError < Exception
end

getter vm : VM
getter context : XephyrContext
getter context_process : ProcessSupervisor

def initialize(@vm : VM)
  display = @vm.display
  raise "QEMU VM did not provide a display" if display.nil?

  @context_process = ProcessSupervisor.new(
    "xephyr.context",
    {
      "DISPLAY_TARGET" => display,
      "XEPHYR_LOG_LEVEL" => ENV.fetch("XEPHYR_LOG_LEVEL", "INFO"),
    }
  )
  @context = XephyrContext.new(display, Global.amqp_channel)
end

include WaitForText
include Execute

def terminate : Bool
  result = false

  begin
    @context.stop
  ensure
    begin
      @context_process.terminate
    ensure
      result = @vm.terminate
    end
  end

  result
end
