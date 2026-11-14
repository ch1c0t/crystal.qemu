require "spec"
require "../src/qemu"

describe QEMU::CommandResult do
  it "reports a successful command" do
    QEMU::CommandResult.new(0, "ok", "").success?.should be_true
  end

  it "reports a failed command" do
    QEMU::CommandResult.new(1, "", "failed").success?.should be_false
  end
end

describe QEMU::ISOResolver do
  it "expands and validates an explicit ISO path" do
    path = File.join(Dir.tempdir, "qemu-iso-resolver-#{Process.pid}-#{Random.rand(1_000_000)}.iso")
    File.write(path, "test ISO")

    begin
      QEMU::ISOResolver.resolve("alpine", path).should eq(File.expand_path(path))
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "rejects a file that is not an ISO" do
    path = File.join(Dir.tempdir, "qemu-iso-resolver-#{Process.pid}-#{Random.rand(1_000_000)}.img")
    File.write(path, "test image")

    begin
      expect_raises(Exception, "Not a non-empty ISO file") do
        QEMU::ISOResolver.resolve("alpine", path)
      end
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end
