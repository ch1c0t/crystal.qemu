getter run_id : String
getter bundle_root : String
getter runs_root : String
getter directory : String
getter repository_root : String
getter packages_directory : String
getter tools_directory : String
getter keys_directory : String
getter apk_root : String
getter verify_root : String
getter host_directory : String
getter host_latest_pointer : String
getter latest_pointer_contents : String

def initialize(
  branch : String,
  shared_directory : String,
  timestamp : Time,
  nonce : Int64
)
  unless branch =~ /\A[a-zA-Z0-9._-]+\z/
    raise ArgumentError.new("Invalid Alpine branch: #{branch.inspect}")
  end
  raise ArgumentError.new("Alpine bundle run nonce must not be negative") if nonce < 0

  @run_id = "#{branch}-#{timestamp.to_s("%Y%m%dT%H%M%SZ")}-#{nonce.to_s(16)}"

  @bundle_root = "/mnt/shared/alpine-bundles"
  @runs_root = "#{@bundle_root}/runs"
  @directory = "#{@runs_root}/#{@run_id}"
  @repository_root = "#{@directory}/repository"
  @packages_directory = "#{@repository_root}/x86_64"
  @tools_directory = "#{@directory}/tools"
  @keys_directory = "#{@directory}/keys"
  @apk_root = "#{@directory}/apk-root"
  @verify_root = "#{@directory}/verify-root"

  host_shared_directory = shared_directory.sub(/\/+\z/, "")
  @host_directory = File.join(host_shared_directory, "alpine-bundles", "runs", @run_id)
  @host_latest_pointer = File.join(host_shared_directory, "alpine-bundles", "LATEST")
  @latest_pointer_contents = "runs/#{@run_id}"
end

def self.new_id(branch : String) : String
  timestamp = Time.utc
  nonce = Random.rand(0_i64..Int64::MAX)
  timestamp_text = timestamp.to_s("%Y%m%dT%H%M%SZ")

  unless branch =~ /\A[a-zA-Z0-9._-]+\z/
    raise ArgumentError.new("Invalid Alpine branch: #{branch.inspect}")
  end

  "#{branch}-#{timestamp_text}-#{nonce.to_s(16)}"
end
