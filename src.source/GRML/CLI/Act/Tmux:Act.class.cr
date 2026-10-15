def validate_arguments
  if @arguments.size == 2 && @arguments[0] == "--iso"
    @boot_iso_path = @arguments[1]
  else
    unless @arguments.empty?
      STDERR.puts "Usage: grml.agent tmux [--iso PATH]"
      exit 1
    end
  end
end

protected def perform(agent : GRML::Agent) : Nil
  Log.info { "Starting tmux in the GRML shell" }
  agent.interaction.type("tmux")
  agent.vm.send_key("ret")
  Log.info { "GRML agent is running tmux. Press Ctrl-C to terminate the VM." }
  sleep
end
