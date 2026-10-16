property name : String?
property memory : String
property cpus : Int32
property iso_path : String?
property shared_path : String
property monitor_path : String
property guest_agent_path : String

getter display : String? = nil

def initialize(
  @iso_path : String? = nil,
  @name = nil,
  @memory = "6G",
  @cpus = 2,
  shared_path : String? = nil,
  @monitor_path = "/tmp/qmp-guest-#{Process.pid}-#{Random.rand(100000)}.sock",
  @guest_agent_path = "/tmp/qga-guest-#{Process.pid}-#{Random.rand(100000)}.sock",
  auto_start : Bool = true
)
  @shared_path = shared_path || (File.exists?("./shared") ? "./shared/" : "#{ENV["HOME"]}/shared/")

  if auto_start
    unless start
      raise "Failed to initialize and start QEMU guest"
    end
  end
end

include Start
include VerifySharedDirectory
include Terminate
include ExecuteQMP

def running? : Bool
  !@display.nil?
end
