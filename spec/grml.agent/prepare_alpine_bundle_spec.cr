require "spec"
require "../../src/grml"

class GRMLBundlePreparationFakeVM
  getter shared_path : String

  def initialize(@shared_path : String = "/shared")
  end
end

class GRMLBundlePreparationFakeInteraction
  getter commands = [] of String
  property failure_pattern : String?

  def initialize(@failure_pattern : String? = nil)
  end

  def execute(command : String, timeout : Time::Span = 30.seconds) : QEMU::CommandResult
    @commands << command

    if pattern = @failure_pattern
      if command.includes?(pattern)
        return QEMU::CommandResult.new(17, "", "simulated command failure")
      end
    end

    output = if command == "uname -m"
               "x86_64\n"
             elsif command.includes?("du -sb")
               "Repository root: /mnt/shared/alpine-bundles/runs/test/repository\n" +
                 "APK architecture directory: /mnt/shared/alpine-bundles/runs/test/repository/x86_64\n" +
                 "APK files: 27\nRepository size: 4123016 bytes\n" +
                 "Index: /mnt/shared/alpine-bundles/runs/test/repository/x86_64/APKINDEX.tar.gz\n"
             else
               ""
             end

    QEMU::CommandResult.new(0, output, "")
  end
end

class GRMLBundlePreparationHarness
  getter vm : GRMLBundlePreparationFakeVM
  getter interaction : GRMLBundlePreparationFakeInteraction

  include GRML::Agent::PrepareAlpineBundle

  def initialize(@interaction : GRMLBundlePreparationFakeInteraction)
    @vm = GRMLBundlePreparationFakeVM.new
  end
end

describe GRML::Agent::PrepareAlpineBundle do
  it "verifies downloaded package signatures, installs offline, audits checksums, then publishes" do
    interaction = GRMLBundlePreparationFakeInteraction.new
    agent = GRMLBundlePreparationHarness.new(interaction)
    progress = [] of String

    agent.prepare_alpine_bundle("latest-stable", ->(message : String) { progress << message; nil })

    commands = interaction.commands
    verify_packages = commands.index { |command| command.includes?(" verify ./*.apk") }.not_nil!
    build_index = commands.index { |command| command.includes?("index --rewrite-arch x86_64") }.not_nil!
    offline_install = commands.index { |command| command.includes?("add --initdb alpine-base alpine-keys") }.not_nil!
    write_manifest = commands.index { |command| command.includes?("format=4") }.not_nil!
    checksum_audit = commands.index { |command| command.includes?("sha256sum -c SHA256SUMS") }.not_nil!
    complete_marker = commands.index { |command| command.includes?("mv RUNNING COMPLETE") }.not_nil!
    publish_latest = commands.index { |command| command.includes?("mv -f") && command.includes?("/LATEST") }.not_nil!

    verify_packages.should be < build_index
    build_index.should be < offline_install
    offline_install.should be < write_manifest
    write_manifest.should be < checksum_audit
    checksum_audit.should be < complete_marker
    complete_marker.should be < publish_latest

    commands[verify_packages].should contain("--keys-dir")
    commands[verify_packages].should_not contain("--allow-untrusted")
    commands[offline_install].should contain("--allow-untrusted")
    commands[offline_install].should contain("--no-network")
    commands[checksum_audit].should contain("expected_paths=")
    commands[checksum_audit].should contain("cut -c67- SHA256SUMS")

    progress.any? { |message| message.includes?("[14/14] Publishing the LATEST bundle pointer done") }.should be_true
  end

  it "does not build the local index or publish when package signature verification fails" do
    interaction = GRMLBundlePreparationFakeInteraction.new(" verify ./*.apk")
    agent = GRMLBundlePreparationHarness.new(interaction)

    expect_raises(Exception, "Failed during Verifying downloaded APK package signatures") do
      agent.prepare_alpine_bundle
    end

    interaction.commands.any? { |command| command.includes?("index --rewrite-arch") }.should be_false
    interaction.commands.any? { |command| command.includes?("mv -f") && command.includes?("/LATEST") }.should be_false
  end

  it "does not mark or publish a bundle when the final checksum audit fails" do
    interaction = GRMLBundlePreparationFakeInteraction.new("sha256sum -c SHA256SUMS")
    agent = GRMLBundlePreparationHarness.new(interaction)

    expect_raises(Exception, "Failed during Verifying bundle manifest and every checksum") do
      agent.prepare_alpine_bundle
    end

    interaction.commands.any? { |command| command.includes?("mv RUNNING COMPLETE") }.should be_false
    interaction.commands.any? { |command| command.includes?("mv -f") && command.includes?("/LATEST") }.should be_false
  end
end
