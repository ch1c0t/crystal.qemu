require "./grml.agent/*"

VERSION = "0.0.0"

case ARGV.size
when 1
  case ARGV[0]
  when "-v", "version", "--version"
    puts VERSION
    exit
  when "-h", "help", "--help"
    print_help
    exit
  end
end

require "../logger"
require "../grml"

unless ARGV == ["boot"]
  STDERR.puts "Usage: grml.agent boot"
  exit 1
end

Log.info { "Starting GRML agent" }
agent = GRML::Agent.new

Signal::INT.trap { agent.terminate && exit }
Signal::TERM.trap { agent.terminate && exit }

begin
  agent.boot
  sleep
ensure
  agent.terminate
end
