def disk_options : Array(String)
  return [] of String unless Dir.exists?("./disks")
  Dir.glob("./disks/*").sort.each_with_index.flat_map do |path, index|
    next [] of String unless File.file?(path)
    backend = "grml_startup_disk_#{index}"
    serial = File.basename(path).sub(/\.[^.]+\z/, "")
    device = "virtio-blk-pci,drive=#{backend}"
    device += ",serial=#{serial}" if serial.matches?(/\A[A-Za-z0-9._-]{1,20}\z/)
    ["-drive", "if=none,id=#{backend},file=#{File.expand_path(path)}", "-device", device]
  end.to_a
end
