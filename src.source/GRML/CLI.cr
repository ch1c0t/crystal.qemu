def self.run(arguments : Array(String) = ARGV.dup) : Nil
  args = arguments.dup
  command = args.shift?

  case command
  when "boot"
    Act::Boot.new(args).run
  when "create_alpine_image"
    Act::CreateAlpineImage.new(args).run
  else
    STDERR.puts "Usage: grml.agent boot [--iso PATH] | create_alpine_image [alpine_iso_path]"
    exit 1
  end
end
