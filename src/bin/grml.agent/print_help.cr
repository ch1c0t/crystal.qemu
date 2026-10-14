HELP_MESSAGE = <<-S
grml.agent boots GRML and provides an interactive command line.

Usage:
  grml.agent boot [--iso PATH]
  grml.agent create_alpine_image [alpine_iso_path]
  grml.agent --help
  grml.agent --version

The boot command discovers a GRML ISO in ./cdrom/ (or QEMU_ISO_DIR) unless
--iso is supplied. It advances through GRML boot prompts, waits for the
root@grml shell prompt, and keeps the VM running until Ctrl-C.

The create_alpine_image command boots GRML, then discovers an Alpine ISO in
./cdrom/ (or QEMU_ISO_DIR) unless an explicit Alpine ISO path is supplied.

Logging:
  XEPHYR_LOG_LEVEL=INFO|DEBUG|TRACE (default: INFO)

Use DEBUG for lifecycle and queue diagnostics, or TRACE for per-frame OCR and
stream timing details across grml.agent and xephyr.context. Diagnostics are
written to stderr.
S

def print_help
  puts HELP_MESSAGE
end
