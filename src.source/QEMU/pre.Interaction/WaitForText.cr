def wait_for_text(
  text : String,
  timeout : Time::Span = 60.seconds,
  region : Symbol = :full_screen
) : XephyrContext::State
  wait_for_text(text, timeout, XephyrContext::ScreenRegion.from_symbol(region))
end

def wait_for_text(
  text : String,
  timeout : Time::Span = 60.seconds,
  region : XephyrContext::ScreenRegion = XephyrContext::ScreenRegion.full_screen,
) : XephyrContext::State
  @context.wait_until(text, timeout, region)
rescue error : RuntimeError
  raise error unless error.message == "Timed out waiting for #{text.inspect}"
  raise TimeoutError.new(error.message || "Timed out waiting for text")
end
