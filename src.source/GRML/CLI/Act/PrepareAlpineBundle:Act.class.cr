@branch : String = "latest-stable"

def validate_arguments
  if @arguments.size > 1
    STDERR.puts "Usage: grml.agent prepare_alpine_bundle [alpine_branch]"
    exit 1
  end

  @branch = @arguments.first? || "latest-stable"
end

protected def perform(agent : GRML::Agent) : Nil
  agent.prepare_alpine_bundle(@branch)
end
