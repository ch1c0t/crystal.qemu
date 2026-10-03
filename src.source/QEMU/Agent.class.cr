class Agent
  getter vm : VM
  getter context : XephyrContext
  getter language : String

  @recognizer : XephyrContext::TextRecognizer
  @latest_text = ""
  @text_mutex = Mutex.new

  def initialize(@language : String = "eng", @vm : VM = VM.new)
    display = @vm.display
    raise "QEMU VM did not provide a display" if display.nil?

    @context = XephyrContext.new(display, Global.amqp_channel)
    @recognizer = XephyrContext::TextRecognizer.new(@language)

    @context.each_mutation do |state|
      text = recognize(state)

      @text_mutex.synchronize do
        @latest_text = text
      end
    end
  end

  def wait_for_text(text : String, timeout : Time::Span = 30.seconds) : Bool
    deadline = Time.instant + timeout

    loop do
      return true if @text_mutex.synchronize { @latest_text.includes?(text) }
      return false if Time.instant >= deadline

      sleep 100.milliseconds
    end
  end

  def stop : Bool
    @recognizer.finalize
    @vm.stop
  end

  private def recognize(state : XephyrContext::State) : String
    raw_bytes = state.raw_pixels
    expected_size = state.width.to_i64 * state.height.to_i64 * 4
    raise "Unexpected framebuffer size: #{raw_bytes.size}, expected at least #{expected_size}" if raw_bytes.size < expected_size

    pixels = Slice(UInt8).new(state.width * state.height)
    offset = 0

    state.height.times do |y|
      state.width.times do |x|
        pixel_offset = (y * state.width + x) * 4
        r = raw_bytes[pixel_offset + 2]
        g = raw_bytes[pixel_offset + 1]
        b = raw_bytes[pixel_offset]

        pixels[offset] = ((r.to_i * 299 + g.to_i * 587 + b.to_i * 114) // 1000).to_u8
        offset += 1
      end
    end

    @recognizer.recognize(pixels, state.width, state.height)
  end
end
