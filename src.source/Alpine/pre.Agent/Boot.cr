def boot : Nil
  Log.info { "Waiting for Alpine login prompt" }
  @interaction.wait_for_text("login:", 180.seconds, :third_quadrant)
  Log.info { "Alpine login prompt detected; logging in as root to configure the console font" }
  @interaction.type("root")
  @vm.send_key("ret")
  @interaction.wait_for_text("You can setup the system", 30.seconds, :third_quadrant)
  @interaction.type("sed -i 's|^#\(.*\/community\)$|\1|' /etc/apk/repositories && apk update && apk add font-terminus && setfont /usr/share/consolefonts/ter-132n.psf.gz")
  @vm.send_key("ret")
  Log.info { "Requested font-terminus installation and console font configuration (ter-132n)" }
end
