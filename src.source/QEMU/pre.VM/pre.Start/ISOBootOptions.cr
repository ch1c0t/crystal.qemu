def iso_boot_options : Array(String)
  if iso_path = @iso_path
    ["-cdrom", iso_path, "-boot", "order=d"]
  else
    ["-boot", "order=c"]
  end
end
