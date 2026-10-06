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

require "../qemu"

vm = QEMU::VM.new(
  iso_path: "~/Downloads/ISOs/grml-full-2026.09-amd64.iso"
)
agent = QEMU::Agent.new(vm)

if agent.wait_for_text("Press a key")
  puts "GRML Agent: Press a key detected"
else
  puts "GRML Agent: timed out waiting for Press a key"
end

agent.stop
