getter arguments : Array(String)

def initialize(@arguments : Array(String) = [] of String)
end

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

abstract def perform(agent : GRML::Agent) : Nil
