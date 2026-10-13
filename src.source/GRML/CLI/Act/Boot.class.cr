def initialize(arguments : Array(String) = [] of String)
  unless arguments.empty?
    STDERR.puts "Usage: grml.agent boot"
    exit 1
  end
end

protected def perform(agent : GRML::Agent) : Nil
  Log.info { "GRML agent is running. Press Ctrl-C to terminate the VM." }
  sleep
end
