include WithAgent

def initialize(@iso_path : String? = nil)
end

protected def perform(agent : GRML::Agent) : Nil
  agent.create_alpine_image(@iso_path)
end
