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

require "log"
Log.setup_from_env(default_level: Log::Severity::Info, log_level_env: "XEPHYR_LOG_LEVEL", backend: Log::IOBackend.new(STDERR))

require "../qemu"

unless ARGV == ["boot"]
  STDERR.puts "Usage: grml.agent boot"
  exit 1
end

LOG = Log.for("grml.agent")

LOG.info { "Starting GRML VM" }
vm = QEMU::VM.new(
  iso_path: "#{ENV["HOME"]}/Downloads/ISOs/grml-full-2026.09-amd64.iso"
)
LOG.info { "Starting XephyrContext process" }
agent = QEMU::Agent.new(vm)

Signal::INT.trap { agent.terminate && exit }
Signal::TERM.trap { agent.terminate && exit }

begin
  LOG.info { "Waiting for GRML boot prompt" }
  agent.wait_for_text("Press ENTER to boot", region: :bottom_tenth)
  LOG.info { "Sending Return to GRML boot prompt" }
  vm.send_key("ret")

  LOG.info { "Waiting for GRML key prompt" }
  agent.wait_for_text("Press a key", region: :bottom_tenth)
  LOG.info { "Sending Return to GRML key prompt" }
  vm.send_key("ret")

  LOG.info { "Waiting for GRML shell prompt" }
  agent.wait_for_text("root@grml", 180.seconds, :bottom_tenth)
  LOG.info { "GRML command line ready. Press Ctrl-C to stop the VM." }

  sleep
ensure
  LOG.info { "Terminating GRML agent" }
  if agent.terminate
    LOG.info { "GRML agent terminated" }
  else
    LOG.error { "GRML agent reported a shutdown failure" }
  end
end
