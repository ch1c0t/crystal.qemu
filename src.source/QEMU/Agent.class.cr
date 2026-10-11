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

def wait_for_text(
  text : String,
  timeout : Time::Span = 60.seconds,
  region : Symbol = :full_screen
) : XephyrContext::State
  screen_region = case region
                  when :full_screen  then XephyrContext::ScreenRegion.full_screen
                  when :top_fourth   then XephyrContext::ScreenRegion.top_fourth
                  when :bottom_tenth then XephyrContext::ScreenRegion.bottom_tenth
                  else
                    raise ArgumentError.new("Unknown screen region: #{region.inspect}")
                  end

  wait_for_text(text, timeout, screen_region)
end

def wait_for_text(
  text : String,
  timeout : Time::Span = 60.seconds,
  region : XephyrContext::ScreenRegion
) : XephyrContext::State
  @context.wait_until(text, timeout, region)
rescue error : RuntimeError
  raise error unless error.message == "Timed out waiting for #{text.inspect}"
  raise TimeoutError.new(error.message || "Timed out waiting for text")
end

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
