# qemu

A reusable Crystal library for managing QEMU virtual machines and interacting
with their guests through QEMU Guest Agent, QMP, Xephyr, and
[xephyr.context](https://github.com/ch1c0t/xephyr.context).

## Requirements

- Crystal 1.22 or newer
- QEMU `qemu-system-x86_64`
- `xephyr-run` and `xephyr-kill` from `xephyr.context`
- A running LavinMQ instance configured for
  [global-amqp_channel](https://github.com/ch1c0t/crystal.global-amqp_channel)
- Tesseract OCR and the native X11/Tesseract development libraries when
  building applications that use `QEMU::Interaction`

## Install

Add the shard to `shard.yml`:

```yaml
dependencies:
  qemu:
    github: ch1c0t/crystal.qemu
    branch: main
```

Then require the library:

```crystal
require "qemu"
```

## Main API

- `QEMU::VM` starts, configures, and terminates a QEMU virtual machine.
- `QEMU::Interaction` provides screen text recognition, guest command
  execution, typing, keyboard input, and shared-directory validation.
- `QEMU::GuestAgent` executes shell commands through the QEMU Guest Agent
  socket and returns a `QEMU::CommandResult`.
- `QEMU::ISOResolver` resolves and validates distribution ISO paths.

A minimal lifecycle:

```crystal
require "qemu"

vm = QEMU::VM.new(iso_path: "/path/to/guest.iso")
interaction = QEMU::Interaction.new(vm)

begin
  interaction.wait_for_text("login:", 180.seconds)
ensure
  interaction.terminate
end
```

The library intentionally contains no distribution-specific agent or CLI.
Distribution boot flows and REPL commands live in the separate
[alpine.agent](https://github.com/ch1c0t/alpine.agent) and
[grml.agent](https://github.com/ch1c0t/grml.agent) applications.

## Streaming guest commands

`QEMU::Interaction#execute_streaming` and
`QEMU::GuestAgent#execute_streaming` expose guest stdout and stderr while a
command is still running:

```crystal
result = interaction.execute_streaming("apt-get update", 5.minutes) do |stream, chunk|
  output.write(chunk)
end

raise "Guest command failed (#{result.exit_code})" unless result.success?
```

The callback receives `:stdout` or `:stderr` and each newly available text
chunk. The method also returns a normal `QEMU::CommandResult` containing the
complete output and final exit code. Output is polled every 100 milliseconds
by default; pass a different polling interval as the third argument.

QEMU Guest Agent only includes captured `guest-exec` output in
`guest-exec-status` after the process exits. Streaming therefore redirects
the guest process's stdout and stderr to temporary files in the guest's
`/tmp` directory and reads appended data through QEMU Guest Agent file
operations. The files are removed after normal completion. If a command times
out, its output files are retained in the guest and their paths are included
in the timeout error, because the command may still be running.

Streaming cannot force a program to flush its own userspace buffers. Programs
that buffer output when stdout is not a terminal may need a line-buffering
wrapper such as `stdbuf -oL -eL`, when supported by that program.
