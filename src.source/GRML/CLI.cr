def self.run(arguments : Array(String) = ARGV.dup) : Nil
  args = arguments.dup
  command = args.shift?

  case command
  when "boot"
    Act::Boot.new(args).run
  when "tmux"
    Act::Tmux.new(args).run
  when "create_alpine_image"
    Act::CreateAlpineImage.new(args).run
  when "prepare_alpine_bundle"
    Act::PrepareAlpineBundle.new(args).run
  else
    STDERR.puts "Usage: grml.agent boot [--iso PATH] | tmux [--iso PATH] | prepare_alpine_bundle [alpine_branch] | create_alpine_image [alpine_iso_path]"
    exit 1
  end
end
