def verify_shared_directory : Bool
  unless File.exists?(@shared_path)
    raise "QEMU shared directory does not exist: #{@shared_path}"
  end

  unless File.directory?(@shared_path)
    raise "QEMU shared path is not a directory: #{@shared_path}"
  end

  true
end
