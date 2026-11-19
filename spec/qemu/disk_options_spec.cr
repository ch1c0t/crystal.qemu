require "spec"
require "file_utils"
require "../../src/qemu"

describe QEMU::VM do
  it "assigns a stable serial through the explicit virtio device" do
    directory = File.join(Dir.tempdir, "qemu-disks-#{Process.pid}")
    FileUtils.mkdir_p(File.join(directory, "disks"))
    path = File.join(directory, "disks", "grml-live-build.qcow2")
    File.write(path, "")
    begin
      command = Dir.cd(directory) { QEMU::VM.new(auto_start: false).build_qemu_command }
      command.should contain("if=none,id=grml_startup_disk_0,file=#{path}")
      command.should contain("virtio-blk-pci,drive=grml_startup_disk_0,serial=grml-live-build")
    ensure
      FileUtils.rm_rf(directory)
    end
  end
end
