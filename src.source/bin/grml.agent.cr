require "../qemu"

vm = QEMU::VM.new(
  iso_path: "#{ENV["HOME"]}/Downloads/ISOs/grml-full-2026.09-amd64.iso"
)
agent = QEMU::Agent.new(vm)

begin
  agent.wait_for_text("Press a key")
  puts "GRML Agent: Press a key detected"
rescue QEMU::Agent::TimeoutError
  puts "GRML Agent: timed out waiting for Press a key"
ensure
  agent.stop
end
