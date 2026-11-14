ARCHITECTURE = "x86_64"

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

# Verify downloaded package signatures independently of the unsigned local index.
def package_verification_command : String
  "cd '#{@packages_directory}' && '#{@tools_directory}/apk.static' --keys-dir '#{@keys_directory}' verify ./*.apk"
end

# APK's repository index must describe the architecture directory in which
# all fetched archives are stored. This rewrites upstream noarch entries too.
def repository_index_command : String
  index = "#{@packages_directory}/APKINDEX.tar.gz"
  "cd '#{@packages_directory}' && '#{@tools_directory}/apk.static' --keys-dir '#{@keys_directory}' index --rewrite-arch #{ARCHITECTURE} --output '#{index}' *.apk"
end

# Remove build-only roots, then write a manifest and SHA-256 hashes for every
# file that belongs to the completed bundle payload.
def write_manifest_command(branch : String) : String
  "set -eu; cd '#{@directory}' && " +
    "rm -rf apk-root verify-root && " +
    "test -x tools/apk.static && test -s tools/alpine-chroot-install && " +
    "find keys -type f -name '*.rsa.pub' -size +0c | grep -q . && " +
    "test -s repository/#{ARCHITECTURE}/APKINDEX.tar.gz && " +
    "package_count=$(find repository/#{ARCHITECTURE} -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d '[:space:]') && " +
    "test \"$package_count\" -gt 0 && " +
    "repository_bytes=$(du -sb repository | cut -f1) && " +
    "printf 'format=4\\nrun_id=%s\\nalpine_branch=%s\\narchitecture=%s\\nrepositories=main,community\\nrequested_packages=alpine-base,alpine-keys\\nrepository=repository\\nrepository_architecture=%s\\nalpine_chroot_install_version=0.14.0\\napk_tools_version=2.14.7\\npackage_signature_verification=apk-verify\\npackage_signatures=verified\\nindex_signature=unsigned\\noffline_install=passed\\noffline_install_network=disabled\\npackage_count=%s\\nrepository_bytes=%s\\nchecksum_algorithm=sha256\\n' " +
    "'#{@run_id}' '#{branch}' '#{ARCHITECTURE}' '#{ARCHITECTURE}' \"$package_count\" \"$repository_bytes\" > MANIFEST && " +
    "find MANIFEST repository tools keys -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS"
end

# Audit the marker, manifest, repository contents, and every recorded checksum
# before the run is promoted from RUNNING to COMPLETE.
def verify_manifest_command(branch : String) : String
  "set -eu; cd '#{@directory}' && " +
    "test -s RUNNING && test ! -e COMPLETE && " +
    "grep -Fqx 'run_id=#{@run_id}' RUNNING && " +
    "grep -Fqx 'format=4' MANIFEST && " +
    "grep -Fqx 'run_id=#{@run_id}' MANIFEST && " +
    "grep -Fqx 'alpine_branch=#{branch}' MANIFEST && " +
    "grep -Fqx 'architecture=#{ARCHITECTURE}' MANIFEST && " +
    "grep -Fqx 'repository=repository' MANIFEST && " +
    "grep -Fqx 'repository_architecture=#{ARCHITECTURE}' MANIFEST && " +
    "grep -Fqx 'alpine_chroot_install_version=0.14.0' MANIFEST && " +
    "grep -Fqx 'apk_tools_version=2.14.7' MANIFEST && " +
    "grep -Fqx 'repositories=main,community' MANIFEST && " +
    "grep -Fqx 'requested_packages=alpine-base,alpine-keys' MANIFEST && " +
    "grep -Fqx 'package_signature_verification=apk-verify' MANIFEST && " +
    "grep -Fqx 'package_signatures=verified' MANIFEST && " +
    "grep -Fqx 'index_signature=unsigned' MANIFEST && " +
    "grep -Fqx 'offline_install=passed' MANIFEST && " +
    "grep -Fqx 'offline_install_network=disabled' MANIFEST && " +
    "grep -Fqx 'checksum_algorithm=sha256' MANIFEST && " +
    "test -s repository/#{ARCHITECTURE}/APKINDEX.tar.gz && " +
    "test -x tools/apk.static && test -s tools/alpine-chroot-install && " +
    "test ! -e apk-root && test ! -e verify-root && " +
    "find keys -type f -name '*.rsa.pub' -size +0c | grep -q . && " +
    "package_count=$(find repository/#{ARCHITECTURE} -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d '[:space:]') && " +
    "test \"$package_count\" -gt 0 && grep -Fqx \"package_count=$package_count\" MANIFEST && " +
    "repository_bytes=$(du -sb repository | cut -f1) && grep -Fqx \"repository_bytes=$repository_bytes\" MANIFEST && " +
    "expected_paths=$(find MANIFEST repository tools keys -type f | LC_ALL=C sort) && " +
    "recorded_paths=$(cut -c67- SHA256SUMS | LC_ALL=C sort) && " +
    "test \"$expected_paths\" = \"$recorded_paths\" && " +
    "sha256sum -c SHA256SUMS"
end

def complete_marker_command : String
  "set -eu; cd '#{@directory}' && test -s RUNNING && test ! -e COMPLETE && mv RUNNING COMPLETE"
end

# Publish LATEST by renaming a temporary file on the same filesystem.
def publish_latest_command : String
  "set -eu; test -s '#{@directory}/COMPLETE' && " +
    "grep -Fqx 'run_id=#{@run_id}' '#{@directory}/COMPLETE' && " +
    "tmp=$(mktemp '#{@bundle_root}/.LATEST.XXXXXX') && " +
    "trap 'rm -f \"$tmp\"' 0 && " +
    "printf '%s\\n' '#{@latest_pointer_contents}' > \"$tmp\" && " +
    "mv -f \"$tmp\" '#{@bundle_root}/LATEST'"
end
