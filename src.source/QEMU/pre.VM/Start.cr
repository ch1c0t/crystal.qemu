include BuildQEMUCommand

def start : Bool
  return false if @display

  File.delete(@monitor_path) if File.exists?(@monitor_path)
  File.delete(@guest_agent_path) if File.exists?(@guest_agent_path)

  qemu_cmd = build_qemu_command
  stdout_buffer = IO::Memory.new
  result = Process.run("xephyr-run", [qemu_cmd], shell: false, output: stdout_buffer)

  if result.success?
    @display = stdout_buffer.to_s.strip
    true
  else
    false
  end
end
