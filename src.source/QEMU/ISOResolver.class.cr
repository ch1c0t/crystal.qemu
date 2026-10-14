class ISOResolver
  DEFAULT_DIRECTORY = "./cdrom"

  def self.resolve(distribution : String, path : String? = nil) : String
    return validate(path) if path
    directory = File.expand_path(DEFAULT_DIRECTORY)
    raise "ISO directory does not exist: #{directory}" unless Dir.exists?(directory)
    pattern = /(?i)#{Regex.escape(distribution)}.*\.iso\z/
    candidates = Dir.glob(File.join(directory, "*")).select do |candidate|
      File.file?(candidate) && File.basename(candidate).matches?(pattern) && File.size(candidate) > 0
    end
    case candidates.size
    when 1
      validate(candidates.first)
    when 0
      raise "No #{distribution} ISO found in #{directory}; pass an ISO path explicitly"
    else
      names = candidates.map { |candidate| File.basename(candidate) }.join(", ")
      raise "Multiple #{distribution} ISOs found in #{directory}: #{names}; pass an ISO path explicitly"
    end
  end

  private def self.validate(path : String) : String
    absolute_path = File.expand_path(path)
    unless File.file?(absolute_path) && File.extname(absolute_path).downcase == ".iso" && File.size(absolute_path) > 0
      raise "Not a non-empty ISO file: #{absolute_path}"
    end
    File.open(absolute_path) { }
    absolute_path
  rescue error : File::Error
    raise "Cannot read ISO #{path}: #{error.message}"
  end
end
