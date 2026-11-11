def terminate : Bool
  return true if @terminated
  Log.info { "Terminating Alpine agent" }
  @terminated = @interaction.terminate
  if @terminated
    Log.info { "Alpine agent terminated" }
  else
    Log.error { "Alpine agent reported a shutdown failure" }
  end
  @terminated
end
