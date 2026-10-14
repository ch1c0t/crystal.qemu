def validate_arguments
  if @arguments.size == 2 && @arguments[0] == "--iso"
    @boot_iso_path = @arguments[1]
  else
    unless @arguments.empty?
      STDERR.puts "Usage: grml.agent boot [--iso PATH]"
      exit 1
    end
  end
end

protected def perform(agent : GRML::Agent) : Nil
  Log.info { "GRML agent is running. Press Ctrl-C to terminate the VM." }
  sleep
end
