def build_qemu_command : String
  cmd_parts = ["qemu-system-x86_64"]
  if guest_name = @name
    cmd_parts << "-name" << "'#{guest_name}'"
  end
  cmd_parts.concat([
    "-full-screen", "-m", @memory, "-smp", @cpus.to_s,
    "-enable-kvm", "-vga", "virtio",
    *shared_path_options, *guest_agent_options, *disk_options, *iso_boot_options,
    "-qmp", "unix:#{@monitor_path},server,nowait"
  ])
  cmd_parts.join(" ")
end
