require "./grml.agent/*"

VERSION = "0.0.0"

if ARGV == ["-v"] || ARGV == ["version"] || ARGV == ["--version"]
  puts VERSION
  exit
elsif ARGV == ["-h"] || ARGV == ["help"] || ARGV == ["--help"]
  print_help
  exit
elsif ARGV != ["boot"]
  print_help
  exit 1
end

require "../qemu"

vm = QEMU::VM.new(
  iso_path: "#{ENV["HOME"]}/Downloads/ISOs/grml-full-2026.09-amd64.iso"
)
agent = QEMU::Agent.new(vm)

begin
  agent.wait_for_text("Press ENTER to boot", region: :bottom_tenth)
  vm.send_key("ret")

  agent.wait_for_text("Press a key", region: :bottom_tenth)
  vm.send_key("ret")

  agent.wait_for_text("root@grml", 180.seconds, :bottom_tenth)
  puts "GRML command line ready. Press Ctrl-C to stop the VM."

  loop { sleep 1.second }
ensure
  agent.terminate
end
