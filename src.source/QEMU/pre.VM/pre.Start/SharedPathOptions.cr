def shared_path_options
  [
    "-fsdev", "local,security_model=mapped,id=shared0,path=#{@shared_path}",
    "-device", "virtio-9p-pci,fsdev=shared0,mount_tag=shared0",
  ]
end
