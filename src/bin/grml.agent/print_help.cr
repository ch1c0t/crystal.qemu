HELP_MESSAGE = <<-S
grml.agent boots GRML and provides an interactive command line.

Usage:
  grml.agent boot [--iso PATH]
  grml.agent tmux [--iso PATH]
  grml.agent prepare_alpine_bundle [alpine_branch]
  grml.agent create_alpine_image [alpine_iso_path]
  grml.agent --help
  grml.agent --version

The boot command discovers a GRML ISO in ./cdrom/ (or QEMU_ISO_DIR) unless
--iso is supplied. It advances through GRML boot prompts, verifies the QEMU
Guest Agent and shared directory, then starts a custom Tmux REPL in the same
booted guest. The REPL stays connected to that guest until the session is
closed or Ctrl-C is pressed.

REPL commands:
  ocr
    Recognize text in the latest captured GRML display frame.
  prepare_alpine_bundle [alpine_branch]
    Fetch the recursive dependency closure of alpine-base and alpine-keys
    from Alpine main and community, then store it under
    /mnt/shared/alpine-bundles/runs/<run_id>. The default branch is
    latest-stable. Each invocation creates a unique UTC timestamped run.
    Downloaded APK signatures are checked with the embedded Alpine public
    keys. A local x86_64 APK index is generated and an isolated installation
    is tested with networking disabled. The operation writes MANIFEST and
    SHA256SUMS, verifies every listed checksum, marks the run COMPLETE, and
    atomically updates LATEST only after verification succeeds.
    See docs/alpine-offline-bundle.md for the artifact layout, checks,
    trust model, and failure behavior.

The repository root is repository/; APK files and APKINDEX.tar.gz are stored
under repository/x86_64/. The locally generated APK index is unsigned. Since
APK requires accepting that local index, the isolated install test uses
--allow-untrusted; package archives are independently signature-verified
before that test. The bundle is an offline package repository snapshot, not
a bootable Alpine root filesystem or disk image.

The one-shot prepare_alpine_bundle CLI command remains available for scripts.
It starts and terminates its own GRML VM and reports phase-level progress.
Package-manager output is collected when each guest command finishes; it is
not streamed line by line during the operation.

The tmux command boots GRML, waits for the shell prompt, types "tmux", and
presses Enter. It keeps the VM running until Ctrl-C.

The create_alpine_image command boots GRML, then discovers an Alpine ISO in
./cdrom/ (or QEMU_ISO_DIR) unless an explicit Alpine ISO path is supplied.

REPL:
  GRML_AGENT_REPL_FOCUS=true|false (default: true)
    true  Switch the current Tmux client to the REPL session.
    false Keep the client in the boot pane; switch manually with:
          tmux switch-client -t grml

Logging:
  XEPHYR_LOG_LEVEL=INFO|DEBUG|TRACE (default: INFO)

Use DEBUG for lifecycle and queue diagnostics, or TRACE for per-frame OCR and
stream timing details across grml.agent and xephyr.context. Diagnostics are
written to stderr.
S

def print_help
  puts HELP_MESSAGE
end
