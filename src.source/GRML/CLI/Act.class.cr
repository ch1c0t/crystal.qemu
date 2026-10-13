getter arguments : Array(String)

def initialize(@arguments : Array(String) = ARGV.dup)
end

def run : Nil
  command, iso_path = parse_arguments
  Log.info { "Starting GRML agent command: #{command}" }
  agent = GRML::Agent.new

  Signal::INT.trap { agent.terminate && exit }
  Signal::TERM.trap { agent.terminate && exit }

  begin
    agent.boot
    if command == "create_alpine_image"
      agent.create_alpine_image(iso_path)
    else
      sleep
    end
  ensure
    agent.terminate
  end
end

private def parse_arguments : Tuple(String, String?)
  args = @arguments.dup
  command = args.shift?
  unless command == "boot" || command == "create_alpine_image"
    usage_error
  end

  iso_path = args.shift?
  if (command == "boot" && iso_path) || !args.empty?
    usage_error
  end

  {command, iso_path}
end

private def usage_error : NoReturn
  STDERR.puts "Usage: grml.agent <boot|create_alpine_image> [alpine_iso_path]"
  exit 1
end
