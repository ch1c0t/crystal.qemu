def guest_agent_options
  [
    "-chardev", "socket,path=#{@guest_agent_path},server=on,wait=off,id=qga0",
    "-device", "virtio-serial-pci",
    "-device", "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0",
  ]
end
