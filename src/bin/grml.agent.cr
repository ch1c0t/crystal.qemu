require "../qemu"

unless ARGV == ["boot"]
  STDERR.puts "Usage: grml.agent boot"
  exit 1
end

vm = QEMU::VM.new(
  iso_path: "#{ENV["HOME"]}/Downloads/ISOs/grml-full-2026.09-amd64.iso"
)
agent = QEMU::Agent.new(vm)

interrupted = false
Signal::INT.trap { interrupted = true }
Signal::TERM.trap { interrupted = true }

begin
  agent.wait_for_text("Press ENTER to boot", region: :bottom_tenth)
  vm.send_key("ret")

  agent.wait_for_text("Press a key", region: :bottom_tenth)
  vm.send_key("ret")

  agent.wait_for_text("root@grml", 180.seconds, :bottom_tenth)
  puts "GRML command line ready. Press Ctrl-C to stop the VM."

  sleep 100.milliseconds until interrupted
ensure
  Signal::INT.reset
  Signal::TERM.reset
  agent.terminate
end
