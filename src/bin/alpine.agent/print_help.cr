HELP_MESSAGE = <<-S
alpine.agent boots an Alpine Linux ISO or an installed virtual disk.

Usage:
  alpine.agent boot
  alpine.agent --help
  alpine.agent --version

If ~/Downloads/ISOs/alpine-extended-3.24.2-x86_64.iso exists, boot it first.
Otherwise, attach regular files from ./disks/ and boot from disk. Waits for the
Alpine login prompt and keeps the VM running until Ctrl-C.

Logging:
  XEPHYR_LOG_LEVEL=INFO|DEBUG|TRACE (default: INFO)
S

def print_help
  puts HELP_MESSAGE
end
