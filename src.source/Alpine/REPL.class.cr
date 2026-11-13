FOCUS_ENV = "ALPINE_AGENT_REPL_FOCUS"

def self.focus? : Bool
  value = ENV.fetch(FOCUS_ENV, "true").strip.downcase

  case value
  when "1", "true", "yes", "on"
    true
  when "0", "false", "no", "off"
    false
  else
    raise ArgumentError.new("#{FOCUS_ENV} must be a boolean (true/false, yes/no, on/off, or 1/0); got #{value.inspect}")
  end
end

@definition : TmuxREPL::Definition
@started = false
@stopped = false

def initialize(@agent : Agent)
  @definition = TmuxREPL.define("alpine") do |repl|
    repl.on_command("ocr") do |context, arguments|
      raise ArgumentError.new("Usage: ocr") unless arguments.empty?

      result = @agent.interaction.latest_ocr
      if error = result.error
        raise "OCR failed for frame #{result.timestamp}: #{error}"
      end

      if result.text.strip.empty?
        context.puts("(no text recognized)")
      else
        context.write(result.text)
      end
    end
  end
end

def run : Nil
  Signal::INT.trap { terminate_on_signal }
  Signal::TERM.trap { terminate_on_signal }

  begin
    focus = self.class.focus?
    @definition.start(focus: focus)
    @started = true

    if focus
      Log.info { "Alpine REPL started in session 'alpine'." }
    else
      Log.info { "Alpine REPL started in session 'alpine'; switch to it with: tmux switch-client -t alpine" }
    end

    @definition.serve
  ensure
    stop
  end
end

def stop : Nil
  return if @stopped

  @stopped = true
  @definition.stop if @started
end

private def terminate_on_signal : Nil
  begin
    stop
  ensure
    @agent.terminate
    exit
  end
end
