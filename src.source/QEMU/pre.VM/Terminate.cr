def terminate : Bool
  if target_display = @display
    result = Process.run("xephyr-kill", [target_display], shell: false)
    File.delete(@monitor_path) if File.exists?(@monitor_path)
    File.delete(@guest_agent_path) if File.exists?(@guest_agent_path)

    if result.success?
      @display = nil
      true
    else
      false
    end
  else
    false
  end
end
