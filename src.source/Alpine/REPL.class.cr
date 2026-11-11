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

@recognizer : XephyrContext::TextRecognizer
@definition : TmuxREPL::Definition

def initialize(@agent : Agent)
  @recognizer = XephyrContext::TextRecognizer.new
  @definition = TmuxREPL.define("alpine") do |repl|
    repl.on_command("ocr") do |context, arguments|
      raise ArgumentError.new("Usage: ocr") unless arguments.empty?

      text = @recognizer.recognize(@agent.interaction.latest_state)
      if text.empty?
        context.puts("(no text recognized)")
      else
        context.write(text)
      end
    end
  end
end

def run : Nil
  started = false
  focus = self.class.focus?

  begin
    @definition.start(focus: focus)
    started = true

    if focus
      Log.info { "Alpine REPL started in session 'alpine'." }
    else
      Log.info { "Alpine REPL started in session 'alpine'; switch to it with: tmux switch-client -t alpine" }
    end

    @definition.serve
  ensure
    begin
      @definition.stop if started
    ensure
      @recognizer.close
    end
  end
end
