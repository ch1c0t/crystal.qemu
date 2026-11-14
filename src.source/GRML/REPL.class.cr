FOCUS_ENV = "GRML_AGENT_REPL_FOCUS"
DEFAULT_ALPINE_BRANCH = "latest-stable"

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

def self.alpine_branch(arguments : Array(String)) : String
  if arguments.size > 1
    raise ArgumentError.new("Usage: prepare_alpine_bundle [alpine_branch]")
  end

  branch = arguments.first? || DEFAULT_ALPINE_BRANCH
  unless branch =~ /\A[a-zA-Z0-9._-]+\z/
    raise ArgumentError.new("Invalid Alpine branch: #{branch.inspect}")
  end

  branch
end

# Keep this operation on the existing agent. The caller may invoke it
# repeatedly without creating another VM or reconnecting to the guest.
def self.prepare_alpine_bundle(
  agent : T,
  arguments : Array(String),
  progress : Proc(String, Nil)? = nil
) : String forall T
  branch = alpine_branch(arguments)
  agent.prepare_alpine_bundle(branch, progress)
  "Prepared Alpine offline bundle (branch: #{branch})."
end

def self.build_definition(agent : T) : TmuxREPL::Definition forall T
  TmuxREPL.define("grml") do |repl|
    repl.on_command("ocr") do |context, arguments|
      raise ArgumentError.new("Usage: ocr") unless arguments.empty?

      result = agent.interaction.latest_ocr
      if error = result.error
        raise "OCR failed for frame #{result.timestamp}: #{error}"
      end

      if result.text.strip.empty?
        context.puts("(no text recognized)")
      else
        context.write(result.text)
      end
    end

    repl.on_command("prepare_alpine_bundle") do |context, arguments|
      progress = ->(message : String) { context.puts(message) }
      GRML::REPL.prepare_alpine_bundle(agent, arguments, progress)
      nil
    end
  end
end

def self.run(agent : Agent) : Nil
  definition = build_definition(agent)
  started = false

  Signal::INT.trap do
    begin
      definition.stop if started
    ensure
      agent.terminate
      exit
    end
  end
  Signal::TERM.trap do
    begin
      definition.stop if started
    ensure
      agent.terminate
      exit
    end
  end

  begin
    focus = focus?
    definition.start(focus: focus)
    started = true

    if focus
      Log.info { "GRML REPL started in session 'grml'." }
    else
      Log.info { "GRML REPL started in session 'grml'; switch to it with: tmux switch-client -t grml" }
    end

    definition.serve
  ensure
    definition.stop if started
  end
end
