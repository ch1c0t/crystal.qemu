require "spec"
require "file_utils"
require "../../src/qemu"

describe QEMU::VM do
  it "assigns a stable virtio serial from the disk image name" do
    directory = File.join(Dir.tempdir, "qemu-disks-#{Process.pid}")
    FileUtils.mkdir_p(File.join(directory, "disks"))
    path = File.join(directory, "disks", "grml-live-build.qcow2")
    File.write(path, "")
    begin
      command = Dir.cd(directory) { QEMU::VM.new(auto_start: false).build_qemu_command }
      command.should contain("file=#{path},if=virtio,serial=grml-live-build")
    ensure
      FileUtils.rm_rf(directory)
    end
  end
end
