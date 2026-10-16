def self.run(arguments : Array(String) = ARGV.dup) : Nil
  args = arguments.dup
  command = args.shift?

  case command
  when "boot"
    Act::Boot.new(args).run
  else
    STDERR.puts "Usage: alpine.agent boot | --help | --version"
    exit 1
  end
end
