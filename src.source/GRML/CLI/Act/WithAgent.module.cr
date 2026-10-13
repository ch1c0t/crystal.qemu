def run : Nil
  agent = GRML::Agent.new

  Signal::INT.trap { agent.terminate && exit }
  Signal::TERM.trap { agent.terminate && exit }

  begin
    agent.boot
    perform(agent)
  ensure
    agent.terminate
  end
end
