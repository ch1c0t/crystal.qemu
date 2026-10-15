getter vm : QEMU::VM
getter interaction : QEMU::Interaction

def initialize(iso_path : String? = nil)
  resolved_iso = QEMU::ISOResolver.resolve("grml", iso_path)
  @vm = QEMU::VM.new(iso_path: resolved_iso)
  Log.info { "Started a QEMU::VM with #{@vm.iso_path}" }
  @interaction = QEMU::Interaction.new(@vm)
  @terminated = false
end

include Boot
include VerifySharedDirectory
include CreateAlpineImage
include Terminate
