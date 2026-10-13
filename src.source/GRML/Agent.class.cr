getter vm : QEMU::VM
getter interaction : QEMU::Agent

def initialize(
  iso_path : String = "#{ENV["HOME"]}/Downloads/ISOs/grml-full-2026.09-amd64.iso"
)
  @vm = QEMU::VM.new(iso_path: iso_path)
  @interaction = QEMU::Agent.new(@vm)
  @terminated = false
end

def boot : Nil
  Log.info { "Waiting for GRML boot prompt" }
  @interaction.wait_for_text("Press ENTER to boot", region: :bottom_tenth)
  Log.info { "Sending Return to GRML boot prompt" }
  @vm.send_key("ret")

  Log.info { "Waiting for GRML key prompt" }
  @interaction.wait_for_text("Press a key", region: :bottom_tenth)
  Log.info { "Sending Return to GRML key prompt" }
  @vm.send_key("ret")

  Log.info { "Waiting for GRML shell prompt" }
  @interaction.wait_for_text("root@grml", 180.seconds, :bottom_tenth)
  Log.info { "GRML command line ready. Press Ctrl-C to terminate the VM." }
end

def terminate : Bool
  return true if @terminated

  Log.info { "Terminating GRML agent" }
  @terminated = @interaction.terminate
  if @terminated
    Log.info { "GRML agent terminated" }
  else
    Log.error { "GRML agent reported a shutdown failure" }
  end
  @terminated
end
