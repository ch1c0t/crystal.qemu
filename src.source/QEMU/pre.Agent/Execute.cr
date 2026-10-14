def execute(command : String, timeout : Time::Span = 30.seconds) : CommandResult
  GuestAgent.new(@vm.guest_agent_path).execute(command, timeout)
end
