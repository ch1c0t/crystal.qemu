class TimeoutError < Exception
end

getter vm : VM
getter context : XephyrContext
getter context_process : ProcessSupervisor
getter text_recognition : XephyrContext::TextRecognition

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
  @text_recognition = XephyrContext::TextRecognition.new(@context)
end

def latest_state : XephyrContext::State
  @context.latest_state ||
    raise "No framebuffer snapshot has been received yet."
end

def latest_ocr(timeout : Time::Span = 10.seconds) : XephyrContext::TextRecognition::Result
  @text_recognition.wait_for_current_state(timeout)
end

include Type
include WaitForText
include Execute
include Terminate
