def verify_shared_directory : QEMU::CommandResult
  filename = ".grml-shared-test-#{Process.pid}-#{Random.rand(100000)}"
  guest_path = "/mnt/shared/#{filename}"
  host_path = File.join(@vm.shared_path, filename)
  FileUtils.mkdir_p(@vm.shared_path)

  command = "mkdir -p /mnt/shared && (mountpoint -q /mnt/shared || mount -t 9p -o trans=virtio shared0 /mnt/shared) && printf 'shared-directory-ok\\n' > #{guest_path} && cat #{guest_path}"
  result = @interaction.execute(command)
  raise "Guest shared-directory check failed: #{result.stderr}#{result.stdout}" unless result.success?
  raise "Unexpected guest output: #{result.stdout.inspect}" unless result.stdout.strip == "shared-directory-ok"
  raise "Guest write is not visible on the host at #{host_path}" unless File.file?(host_path) && File.read(host_path) == "shared-directory-ok\n"

  result
ensure
  begin
    @interaction.execute("rm -f #{guest_path}") if guest_path
  rescue
  end
  File.delete(host_path) if host_path && File.exists?(host_path)
end
