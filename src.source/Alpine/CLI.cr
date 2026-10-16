def self.run(arguments : Array(String) = ARGV.dup) : Nil
  args = arguments.dup
  command = args.shift?
  if command == "boot"
    unless args.empty?
      STDERR.puts "Usage: alpine.agent boot"
      exit 1
    end
    agent = Alpine::Agent.new
    Signal::INT.trap { agent.terminate && exit }
    Signal::TERM.trap { agent.terminate && exit }
    begin
      agent.boot
      Log.info { "Alpine agent is running. Press Ctrl-C to terminate the VM." }
      sleep
    ensure
      agent.terminate
    end
  else
    STDERR.puts "Usage: alpine.agent boot | --help | --version"
    exit 1
  end
end
