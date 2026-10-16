getter vm : QEMU::VM
getter interaction : QEMU::Interaction

def initialize
  disks = Dir.exists?("./disks") ? Dir.glob("./disks/*").select { |path| File.file?(path) && File.size(path) > 0 }.sort : [] of String
  raise "No non-empty virtual disks found in ./disks; install Alpine first" if disks.empty?

  Log.info { "Booting Alpine from #{disks.first}" }
  @vm = QEMU::VM.new(iso_path: nil, name: "Alpine")
  @interaction = QEMU::Interaction.new(@vm)
  @terminated = false
end

module Boot
  def boot : Nil
    Log.info { "Waiting for Alpine login prompt" }
    @interaction.wait_for_text("login:", 180.seconds, :bottom_tenth)
    Log.info { "Alpine login prompt detected" }
  end
end

module Terminate
  def terminate : Bool
    return true if @terminated
    Log.info { "Terminating Alpine agent" }
    @terminated = @interaction.terminate
    @terminated ? Log.info { "Alpine agent terminated" } : Log.error { "Alpine agent reported a shutdown failure" }
    @terminated
  end
end

include Boot
include Terminate
