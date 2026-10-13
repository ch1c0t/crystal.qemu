include WithAgent

protected def perform(agent : GRML::Agent) : Nil
  Log.info { "GRML agent is running. Press Ctrl-C to terminate the VM." }
  sleep
end
