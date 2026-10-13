getter vm : QEMU::VM
getter interaction : QEMU::Agent

def initialize(
  iso_path : String = "#{ENV["HOME"]}/Downloads/ISOs/grml-full-2026.09-amd64.iso"
)
  @vm = QEMU::VM.new(iso_path: iso_path)
  @interaction = QEMU::Agent.new(@vm)
  @terminated = false
end

include Boot
include CreateAlpineImage
include Terminate
