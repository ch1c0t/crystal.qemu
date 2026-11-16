def execute(command : String, timeout : Time::Span = 30.seconds) : CommandResult
  GuestAgent.new(@vm.guest_agent_path).execute(command, timeout)
end


def execute_streaming(
  command : String,
  timeout : Time::Span = 30.seconds,
  poll_interval : Time::Span = 100.milliseconds
) : CommandResult
  GuestAgent.new(@vm.guest_agent_path).execute_streaming(command, timeout, poll_interval)
end

def execute_streaming(
  command : String,
  timeout : Time::Span = 30.seconds,
  poll_interval : Time::Span = 100.milliseconds,
  &on_output : Symbol, String ->
) : CommandResult
  GuestAgent.new(@vm.guest_agent_path).execute_streaming(command, timeout, poll_interval, &on_output)
end
