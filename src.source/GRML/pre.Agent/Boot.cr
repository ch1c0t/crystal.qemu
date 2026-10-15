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
  Log.info { "GRML command line ready; checking QEMU Guest Agent" }

  result = @interaction.execute("printf 'qemu-guest-agent-ok\\n'")
  unless result.success? && result.stdout.strip == "qemu-guest-agent-ok"
    raise "QEMU Guest Agent test failed (exit=#{result.exit_code}, stdout=#{result.stdout.inspect}, stderr=#{result.stderr.inspect})"
  end

  Log.info { "QEMU Guest Agent is operational" }
  Log.info { "Setting GRML console font size to 12x24" }
  result = @interaction.execute("sed -i 's/^FONTSIZE=.*/FONTSIZE=\\\"12x24\\\"/' /etc/default/console-setup && grep -q '^FONTSIZE=\\\"12x24\\\"  Log.info { "Verifying GRML shared directory" }
  verify_shared_directory
  Log.info { "GRML shared directory is operational" }
  Log.info { "Press Ctrl-C to terminate the VM." }
end
 /etc/default/console-setup && setupcon")
  unless result.success?
    raise "Could not configure GRML console font size (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
  end
  Log.info { "GRML console font size set to 12x24" }
  Log.info { "Verifying GRML shared directory" }
  verify_shared_directory
  Log.info { "GRML shared directory is operational" }
  Log.info { "Press Ctrl-C to terminate the VM." }
end
