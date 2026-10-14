getter vm : QEMU::VM
getter interaction : QEMU::Agent

def initialize(iso_path : String? = nil)
  resolved_iso = QEMU::ISOResolver.resolve("grml", iso_path)
  @vm = QEMU::VM.new(iso_path: resolved_iso)
  @interaction = QEMU::Agent.new(@vm)
  @terminated = false
end

include Boot
include VerifySharedDirectory
include CreateAlpineImage
include Terminate
