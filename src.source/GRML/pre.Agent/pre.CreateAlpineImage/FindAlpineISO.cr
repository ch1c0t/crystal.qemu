private def find_alpine_iso(iso_path : String?) : String
  if path = iso_path
    validate_alpine_iso(path)
    return path
  end

  directory = File.expand_path(@vm.shared_path)
  raise "Shared directory does not exist: #{directory}" unless Dir.exists?(directory)

  candidates = Dir.glob(File.join(directory, "*")).select do |path|
    File.file?(path) && File.basename(path).matches?(/(?i)alpine.*\.iso\z/) && File.size(path) > 0
  end

  case candidates.size
  when 0
    raise "No non-empty Alpine Linux ISO found in shared directory: #{directory}"
  when 1
    validate_alpine_iso(candidates.first)
    candidates.first
  else
    raise "Multiple Alpine Linux ISOs found in #{directory}; pass the desired ISO path explicitly"
  end
end

private def validate_alpine_iso(path : String) : Nil
  unless File.file?(path) &&
         File.basename(path).matches?(/(?i)alpine.*\.iso\z/) &&
         File.size(path) > 0
    raise "Not a non-empty Alpine Linux ISO file: #{path}"
  end

  File.open(path) { }
rescue error : File::Error
  raise "Cannot read Alpine Linux ISO #{path}: #{error.message}"
end
