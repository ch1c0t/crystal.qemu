getter vm : QEMU::VM
getter interaction : QEMU::Interaction

def initialize
  iso = File.expand_path(File.join(ENV.fetch("HOME"), "Downloads", "ISOs", "alpine-extended-3.24.2-x86_64.iso"))
  iso_path = File.file?(iso) && File.size(iso) > 0 ? iso : nil
  disks = Dir.exists?("./disks") ? Dir.glob("./disks/*").select { |path| File.file?(path) && File.size(path) > 0 }.sort : [] of String

  if iso_path
    Log.info { "Booting Alpine ISO from #{iso_path}" }
  elsif disks.empty?
    raise "Alpine ISO not found at #{iso}; no non-empty virtual disks found in ./disks"
  else
    Log.info { "Booting Alpine from disk #{disks.first}" }
  end
  @vm = QEMU::VM.new(iso_path: iso_path, name: "Alpine")
  @interaction = QEMU::Interaction.new(@vm)
  @terminated = false
end

module Boot
  def boot : Nil
    Log.info { "Waiting for Alpine login prompt" }
    @interaction.wait_for_text("login:", 180.seconds, :third_quadrant)
    Log.info { "Alpine login prompt detected; logging in as root to configure the console font" }
    @interaction.type("root")
    @vm.send_key("ret")
    @interaction.wait_for_text("You can setup the system", 30.seconds, :third_quadrant)
    @interaction.type("sed -i 's|^#\(.*\/community\)$|\1|' /etc/apk/repositories && apk update && apk add font-terminus && setfont /usr/share/consolefonts/ter-132n.psf.gz")
    @vm.send_key("ret")
    Log.info { "Requested font-terminus installation and console font configuration (ter-132n)" }
  end
end

module Terminate
  def terminate : Bool
    return true if @terminated
    Log.info { "Terminating Alpine agent" }
    @terminated = @interaction.terminate
    if @terminated
      Log.info { "Alpine agent terminated" }
    else
      Log.error { "Alpine agent reported a shutdown failure" }
    end
    @terminated
  end
end

include Boot
include Terminate
