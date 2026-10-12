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

unless ARGV == ["boot"]
  STDERR.puts "Usage: grml.agent boot"
  exit 1
end

vm = QEMU::VM.new(
  iso_path: "#{ENV["HOME"]}/Downloads/ISOs/grml-full-2026.09-amd64.iso"
)
agent = QEMU::Agent.new(vm)

Signal::INT.trap { agent.terminate && exit }
Signal::TERM.trap { agent.terminate && exit }

begin
  agent.wait_for_text("Press ENTER to boot", region: :bottom_tenth)
  vm.send_key("ret")

  agent.wait_for_text("Press a key", region: :bottom_tenth)
  vm.send_key("ret")

  agent.wait_for_text("root@grml", 180.seconds, :bottom_tenth)
  puts "GRML command line ready. Press Ctrl-C to stop the VM."

  sleep
ensure
  agent.terminate
end
