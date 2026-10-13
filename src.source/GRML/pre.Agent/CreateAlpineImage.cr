def create_alpine_image(iso_path : String? = nil) : Nil
  iso = find_alpine_iso(iso_path)
  Log.info { "Found Alpine Linux ISO: #{iso}" }
  raise "Alpine image creation workflow is not implemented yet"
end

include FindAlpineISO
