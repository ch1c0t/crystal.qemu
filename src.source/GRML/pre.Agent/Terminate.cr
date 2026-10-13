def terminate : Bool
  return true if @terminated

  Log.info { "Terminating GRML agent" }
  @terminated = @interaction.terminate
  if @terminated
    Log.info { "GRML agent terminated" }
  else
    Log.error { "GRML agent reported a shutdown failure" }
  end
  @terminated
end
