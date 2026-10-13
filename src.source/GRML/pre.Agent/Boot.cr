def boot : Nil
  Log.info { "Waiting for GRML boot prompt" }
  @interaction.wait_for_text("Press ENTER to boot", region: :bottom_tenth)
  Log.info { "Sending Return to GRML boot prompt" }
  @vm.send_key("ret")

  Log.info { "Waiting for GRML key prompt" }
  @interaction.wait_for_text("Press a key", region: :bottom_tenth)
  Log.info { "Sending Return to GRML key prompt" }
  @vm.send_key("ret")

  Log.info { "Waiting for GRML shell prompt" }
  @interaction.wait_for_text("root@grml", 180.seconds, :bottom_tenth)
  Log.info { "GRML command line ready. Press Ctrl-C to terminate the VM." }
end
