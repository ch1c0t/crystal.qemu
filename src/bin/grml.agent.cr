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

command = ARGV.shift?
unless command == "boot" || command == "create_alpine_image"
  STDERR.puts "Usage: grml.agent <boot|create_alpine_image> [alpine_iso_path]"
  exit 1
end

alpine_iso_path = ARGV.shift?
if (command == "boot" && (alpine_iso_path || !ARGV.empty?)) ||
   (command == "create_alpine_image" && !ARGV.empty?)
  STDERR.puts "Usage: grml.agent <boot|create_alpine_image> [alpine_iso_path]"
  exit 1
end

Log.info { "Starting GRML agent command: #{command}" }
agent = GRML::Agent.new

Signal::INT.trap { agent.terminate && exit }
Signal::TERM.trap { agent.terminate && exit }

begin
  agent.boot
  if command == "create_alpine_image"
    agent.create_alpine_image(alpine_iso_path)
  else
    sleep
  end
ensure
  agent.terminate
end
