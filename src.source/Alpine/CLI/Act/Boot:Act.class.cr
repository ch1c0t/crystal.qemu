def validate_arguments
  unless @arguments.empty?
    STDERR.puts "Usage: alpine.agent boot"
    exit 1
  end
end

protected def perform(agent : Alpine::Agent) : Nil
  Log.info { "Alpine agent is running. Starting REPL." }
  Alpine::REPL.new(agent).run
end
