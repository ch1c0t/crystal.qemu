require "../logger"
require "../qemu"

unless ARGV == ["boot"]
  STDERR.puts "Usage: grml.agent boot"
  exit 1
end

LOG = Log.for("grml.agent")

LOG.info { "Starting GRML agent" }
agent = GRML::Agent.new

Signal::INT.trap { agent.terminate && exit }
Signal::TERM.trap { agent.terminate && exit }

begin
  agent.boot
  sleep
ensure
  agent.terminate
end
