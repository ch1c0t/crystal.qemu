getter exit_code : Int32
getter stdout : String
getter stderr : String

def initialize(@exit_code : Int32, @stdout : String, @stderr : String)
end

def success? : Bool
  @exit_code == 0
end
