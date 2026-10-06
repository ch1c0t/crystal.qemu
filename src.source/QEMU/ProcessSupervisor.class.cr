getter process : Process

def initialize(command : String, env : Hash(String, String))
  @process = Process.new(
    command,
    env: env,
    output: Process::Redirect::Inherit,
    error: Process::Redirect::Inherit
  )
end

def stop : Nil
  return if @process.terminated?

  @process.terminate
  @process.wait
end

def running? : Bool
  !@process.terminated?
end
