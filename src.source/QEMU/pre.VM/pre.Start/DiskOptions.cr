def disk_options : Array(String)
  return [] of String unless Dir.exists?("./disks")
  Dir.glob("./disks/*").sort.flat_map do |path|
    next [] of String unless File.file?(path)
    serial = File.basename(path).sub(/\.[^.]+\z/, "")
    drive = "file=#{File.expand_path(path)},if=virtio"
    drive += ",serial=#{serial}" if serial.matches?(/\A[A-Za-z0-9._-]{1,20}\z/)
    ["-drive", drive]
  end
end
