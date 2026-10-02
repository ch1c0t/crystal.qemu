def build_qemu_command : String
  cmd_parts = ["qemu-system-x86_64"]

  if guest_name = @name
    cmd_parts << "-name" << "'#{guest_name}'"
  end

  cmd_parts.concat([
    "-full-screen",
    "-m", @memory,
    "-smp", @cpus.to_s,
    "-enable-kvm",
    "-vga", "virtio",
    "-fsdev", "local,security_model=mapped,id=shared0,path=#{@shared_path}",
    "-device", "virtio-9p-pci,fsdev=shared0,mount_tag=shared0",
    "-cdrom", @iso_path,
    "-qmp", "unix:#{@monitor_path},server,nowait"
  ])

  cmd_parts.join(" ")
end

def start : Bool
  return false if @display

  File.delete(@monitor_path) if File.exists?(@monitor_path)

  qemu_cmd = build_qemu_command
  stdout_buffer = IO::Memory.new
  result = Process.run("xephyr-run", [qemu_cmd], shell: false, output: stdout_buffer)

  if result.success?
    @display = stdout_buffer.to_s.strip
    true
  else
    false
  end
end
