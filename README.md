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
