HELP_MESSAGE = <<-S
grml.agent boots GRML and provides an interactive command line.

Usage:
  grml.agent boot
  grml.agent --help
  grml.agent --version

The boot command starts the GRML VM, advances through its boot prompts,
waits for the root@grml shell prompt, and keeps the VM running until Ctrl-C.

Logging:
  XEPHYR_LOG_LEVEL=INFO|DEBUG|TRACE (default: INFO)

Use DEBUG for lifecycle and queue diagnostics, or TRACE for per-frame OCR and
stream timing details across grml.agent and xephyr.context. Diagnostics are
written to stderr.
S

def print_help
  puts HELP_MESSAGE
end
