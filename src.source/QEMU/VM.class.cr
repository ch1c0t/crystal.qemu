property name : String? 
property memory : String
property cpus : Int32
property iso_path : String
property shared_path : String
property monitor_path : String 

getter display : String? = nil

def initialize(
  @name = nil, 
  @memory = "6G", 
  @cpus = 2, 
  @iso_path = "alpine.iso", 
  @shared_path = "#{ENV["HOME"]}/shared/", 
  @monitor_path = "/tmp/qmp-guest-#{Random.rand(100000)}.sock",
  auto_start : Bool = true
)
  if auto_start
    unless start
      raise "Failed to initialize and start QEMU guest"
    end
  end
end

include Start
include Stop
include ExecuteQMP

def running? : Bool
  !@display.nil?
end
