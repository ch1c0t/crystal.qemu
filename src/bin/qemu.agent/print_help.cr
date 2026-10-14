HELP_MESSAGE = <<-S
qemu.agent boots an ISO using QEMU and Xephyr.

Usage:
  qemu.agent boot <grml|alpine> [--iso PATH]
  qemu.agent --help
  qemu.agent --version

Without --iso, qemu.agent discovers a matching ISO in ./cdrom/.
If multiple matching ISOs are found, specify one with --iso PATH.

Logging:
  XEPHYR_LOG_LEVEL=INFO|DEBUG|TRACE (default: INFO)
S

def print_help
  puts HELP_MESSAGE
end
