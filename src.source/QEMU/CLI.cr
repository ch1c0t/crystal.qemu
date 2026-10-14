def self.run(arguments : Array(String) = ARGV.dup) : Nil
  args = arguments.dup
  command = args.shift?
  distribution = args.shift?.try(&.downcase)
  unless command == "boot" && ["grml", "alpine"].includes?(distribution)
    STDERR.puts "Usage: qemu.agent boot <grml|alpine> [--iso PATH]"
    exit 1
  end
  iso_path = nil.as(String?)
  if args.size == 2 && args[0] == "--iso"
    iso_path = args[1]
  elsif !args.empty?
    STDERR.puts "Usage: qemu.agent boot <grml|alpine> [--iso PATH]"
    exit 1
  end
  iso = ISOResolver.resolve(distribution.not_nil!, iso_path)
  agent = Agent.new(VM.new(iso_path: iso))
  Signal::INT.trap { agent.terminate && exit }
  Signal::TERM.trap { agent.terminate && exit }
  begin
    Log.info { "Booting #{distribution} from #{iso}" }
    sleep
  ensure
    agent.terminate
  end
end
