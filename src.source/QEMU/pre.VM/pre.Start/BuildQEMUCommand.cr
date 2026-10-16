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
    *shared_path_options,
    *guest_agent_options,
    *disk_options,
    *iso_boot_options,
    "-qmp", "unix:#{@monitor_path},server,nowait"
  ])

  cmd_parts.join(" ")
end

def iso_boot_options : Array(String)
  if iso_path = @iso_path
    ["-cdrom", iso_path, "-boot", "order=d"]
  else
    ["-boot", "order=c"]
  end
end

def shared_path_options
  [
    "-fsdev", "local,security_model=mapped,id=shared0,path=#{@shared_path}",
    "-device", "virtio-9p-pci,fsdev=shared0,mount_tag=shared0",
  ]
end

def guest_agent_options
  [
    "-chardev", "socket,path=#{@guest_agent_path},server=on,wait=off,id=qga0",
    "-device", "virtio-serial-pci",
    "-device", "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0",
  ]
end

def disk_options : Array(String)
  return [] of String unless Dir.exists?("./disks")

  Dir.glob("./disks/*").sort.flat_map do |path|
    next [] of String unless File.file?(path)

    ["-drive", "file=#{File.expand_path(path)},if=virtio"]
  end
end
