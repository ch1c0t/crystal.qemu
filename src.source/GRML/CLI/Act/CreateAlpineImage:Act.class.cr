@iso_path : String?

def validate_arguments
  if @arguments.size > 1
    STDERR.puts "Usage: grml.agent create_alpine_image [alpine_iso_path]"
    exit 1
  end

  @iso_path = @arguments.first?
end

protected def perform(agent : GRML::Agent) : Nil
  agent.create_alpine_image(@iso_path)
end
