def verify_shared_directory : Nil
  token = Random.rand(1..Int64::MAX).to_s
  host_file = File.join(@vm.shared_path, ".qemu-host-check-#{token}")
  guest_host_file = "/mnt/shared/.qemu-host-check-#{token}"
  guest_file = "/mnt/shared/.qemu-guest-check-#{token}"
  File.write(host_file, token)

  begin
    verify_guest_mount
    verify_guest_read(guest_host_file, token)
    verify_guest_write(guest_file, token)
    unless File.read(File.join(@vm.shared_path, File.basename(guest_file))) == token
      raise "Guest-created shared file is not visible to the host"
    end
  ensure
    @interaction.execute("unlink #{guest_host_file} #{guest_file}")
    File.delete(host_file) if File.exists?(host_file)
  end
end

private def verify_guest_mount : Nil
  command = "mkdir -p /mnt/shared && (mountpoint -q /mnt/shared || " +
    "mount -t 9p -o trans=virtio,version=9p2000.L shared0 /mnt/shared)"
  result = @interaction.execute(command)
  raise "Could not mount QEMU shared directory at /mnt/shared" unless result.success?
end

private def verify_guest_read(path : String, expected : String) : Nil
  result = @interaction.execute("cat #{path}")
  unless result.success? && result.stdout.strip == expected
    raise "GRML guest cannot read files from the shared directory"
  end
end

private def verify_guest_write(path : String, token : String) : Nil
  result = @interaction.execute("printf '%s' #{token} > #{path}")
  raise "GRML guest cannot write to the shared directory" unless result.success?
end
