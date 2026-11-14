def prepare_alpine_bundle(branch : String = "latest-stable", progress : Proc(String, Nil)? = nil) : Nil
  run = GRML::AlpineBundleRun.new(
    branch,
    @vm.shared_path,
    Time.utc,
    Random.rand(0_i64..Int64::MAX)
  )
  bundle = run.directory
  repository = run.repository_root
  packages = run.packages_directory
  tools = run.tools_directory
  keys = run.keys_directory
  arch = GRML::AlpineBundleRun::ARCHITECTURE
  apk_root = run.apk_root
  mirror = "https://dl-cdn.alpinelinux.org/alpine"
  started_at = Time.instant

  report_bundle_progress(progress, "Preparing Alpine offline bundle")
  report_bundle_progress(progress, "Alpine branch: #{branch}")
  report_bundle_progress(progress, "Run ID: #{run.run_id}")
  report_bundle_progress(progress, "Bundle directory: #{run.host_directory}")
  report_bundle_progress(progress, "LATEST pointer: #{run.host_latest_pointer}")

  report_bundle_stage(1, "Checking GRML architecture", progress) do
    verify_bundle_architecture
  end

  report_bundle_stage(2, "Creating an isolated bundle run directory", progress) do
    run_bundle_command(
      "mkdir -p '#{run.runs_root}' && " +
      "mkdir '#{bundle}' && " +
      "mkdir -p '#{tools}' '#{keys}' '#{packages}' '#{apk_root}' && " +
      "printf 'run_id=%s\\n' '#{run.run_id}' > '#{bundle}/RUNNING'"
    )
  end

  report_bundle_stage(3, "Downloading and verifying alpine-chroot-install", progress) do
    run_bundle_command(
      "cd '#{tools}' && curl -fsSL " +
      "https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/v0.14.0/alpine-chroot-install " +
      "-o alpine-chroot-install"
    )
    run_bundle_command(
      "cd '#{tools}' && printf '%s  %s\\n' " +
      "a181c3b3ebc2d7eb7e44d0178dd4ba78a2c9d3ae136f9192317e0bf9262fac3b alpine-chroot-install | sha256sum -c -"
    )
  end

  report_bundle_stage(4, "Downloading and verifying apk.static", progress) do
    run_bundle_command(
      "cd '#{tools}' && curl -fsSL " +
      "https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v2.14.7/x86_64/apk.static " +
      "-o apk.static"
    )
    run_bundle_command(
      "cd '#{tools}' && printf '%s  %s\\n' " +
      "bdd044e0fd6cc388c5e571e1093efa5f35f7767cc5aa338b0a2576a429009a62 apk.static | sha256sum -c -"
    )
    run_bundle_command("chmod +x '#{tools}/apk.static'")
  end

  report_bundle_stage(5, "Extracting and installing Alpine signing keys", progress) do
    extract_alpine_keys(tools, keys)
    run_bundle_command("mkdir -p '#{apk_root}/etc/apk/keys' && cp '#{keys}'/*.rsa.pub '#{apk_root}/etc/apk/keys/'")
  end

  report_bundle_stage(6, "Fetching Alpine packages from main and community", progress) do
    fetch_alpine_packages(packages, apk_root, tools, mirror, branch)
  end

  report_bundle_stage(7, "Verifying downloaded APK package signatures", progress) do
    run_bundle_command(run.package_verification_command)
  end

  report_bundle_stage(8, "Building the local APK repository index for x86_64", progress) do
    run_bundle_command(run.repository_index_command)
  end

  report_bundle_stage(9, "Checking the local APK repository", progress) do
    inspect_local_repository(bundle, repository, packages, progress)
  end

  report_bundle_stage(10, "Verifying offline installation", progress) do
    verify_offline_repository(repository, bundle, tools, keys, arch)
  end

  report_bundle_stage(11, "Writing bundle manifest and SHA-256 checksums", progress) do
    run_bundle_command(run.write_manifest_command(branch))
  end

  report_bundle_stage(12, "Verifying bundle manifest and every checksum", progress) do
    run_bundle_command(run.verify_manifest_command(branch))
  end

  report_bundle_stage(13, "Marking the verified run COMPLETE", progress) do
    run_bundle_command(run.complete_marker_command)
  end

  report_bundle_stage(14, "Publishing the LATEST bundle pointer", progress) do
    run_bundle_command(run.publish_latest_command)
  end

  elapsed = Time.instant - started_at
  report_bundle_progress(progress, "Prepared Alpine offline bundle: #{run.host_directory}")
  report_bundle_progress(progress, "LATEST now contains: #{run.latest_pointer_contents}")
  report_bundle_progress(progress, "Total preparation time: #{elapsed.total_seconds.round(1)}s")
end

private def report_bundle_stage(
  index : Int32,
  title : String,
  progress : Proc(String, Nil)?,
  &block : -> Nil
) : Nil
  label = "[#{index}/14] #{title}"
  started_at = Time.instant
  report_bundle_progress(progress, "#{label} ...")

  begin
    yield
  rescue ex
    elapsed = Time.instant - started_at
    report_bundle_progress(progress, "#{label} FAILED (#{elapsed.total_seconds.round(1)}s)")
    raise "Failed during #{title}: #{ex.message}"
  end

  elapsed = Time.instant - started_at
  report_bundle_progress(progress, "#{label} done (#{elapsed.total_seconds.round(1)}s)")
end

private def report_bundle_progress(progress : Proc(String, Nil)?, message : String) : Nil
  if callback = progress
    callback.call(message)
  else
    Log.info { message }
  end
end

private def verify_bundle_architecture : Nil
  result = @interaction.execute("uname -m")
  raise "Could not detect GRML CPU architecture" unless result.success?
  unless result.stdout.strip == "x86_64"
    raise "Alpine bundle preparation currently supports x86_64 only (found #{result.stdout.strip.inspect})"
  end
end

private def extract_alpine_keys(tools : String, keys : String) : Nil
  script = "#{tools}/alpine-chroot-install"
  command = "awk '/^ALPINE_KEYS=/,/^\\x27$/ { if (NR > 1 && $0 !~ /^ALPINE_KEYS=/ && $0 !~ /^\\x27$/) print }' '#{script}' | " +
    "while IFS= read -r line; do " +
    "id=\${line%%:*}; content=\${line#*:}; " +
    "[ -n \"\${id}\" ] || continue; " +
    "file='#{keys}/alpine-devel@lists.alpinelinux.org-'\${id}'.rsa.pub'; " +
    "printf '%s\\n' '-----BEGIN PUBLIC KEY-----' > \"\${file}\"; " +
    "printf '%b\\n' \"\${content}\" >> \"\${file}\"; " +
    "printf '%s\\n' '-----END PUBLIC KEY-----' >> \"\${file}\"; done"
  run_bundle_command(command)
end

private def fetch_alpine_packages(packages : String, apk_root : String, tools : String, mirror : String, branch : String) : Nil
  command = "'#{tools}/apk.static' --root '#{apk_root}' --keys-dir '#{apk_root}/etc/apk/keys' --no-cache --arch x86_64 " +
    "--repository #{mirror}/#{branch}/main " +
    "--repository #{mirror}/#{branch}/community " +
    "fetch --recursive --output '#{packages}' alpine-base alpine-keys"
  run_bundle_command(command)
end

private def inspect_local_repository(bundle : String, repository : String, packages : String, progress : Proc(String, Nil)?) : Nil
  index = "#{packages}/APKINDEX.tar.gz"
  command = "set -eu; " +
    "if [ ! -d '#{packages}' ]; then " +
    "echo 'Missing APK architecture directory: #{packages}' >&2; " +
    "find '#{bundle}' -maxdepth 4 -print >&2 || true; exit 41; fi; " +
    "if [ ! -s '#{index}' ]; then " +
    "echo 'Missing or empty APK index: #{index}' >&2; " +
    "find '#{bundle}' -maxdepth 4 -print >&2 || true; exit 42; fi; " +
    "package_count=$(find '#{packages}' -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d '[:space:]'); " +
    "if [ \"$package_count\" -eq 0 ]; then " +
    "echo 'No APK package files found in: #{packages}' >&2; " +
    "find '#{bundle}' -maxdepth 4 -print >&2 || true; exit 43; fi; " +
    "repository_bytes=$(du -sb '#{repository}' | cut -f1); " +
    "printf 'Repository root: %s\\nAPK architecture directory: %s\\nAPK files: %s\\nRepository size: %s bytes\\nIndex: %s\\n' " +
    "'#{repository}' '#{packages}' \"$package_count\" \"$repository_bytes\" '#{index}'"

  result = @interaction.execute(command, 300.seconds)
  unless result.success?
    raise "Local APK repository preflight failed (exit=#{result.exit_code}):\n#{result.stderr}\n#{result.stdout}"
  end

  report_bundle_progress(progress, result.stdout.strip)
end

private def verify_offline_repository(repository : String, bundle : String, tools : String, keys : String, arch : String) : Nil
  test_root = "#{bundle}/verify-root"
  run_bundle_command("rm -rf '#{test_root}' && mkdir -p '#{test_root}/etc/apk/keys' && cp '#{keys}'/*.rsa.pub '#{test_root}/etc/apk/keys/'")
  command = "'#{tools}/apk.static' --root '#{test_root}' --keys-dir '#{test_root}/etc/apk/keys' " +
    "--allow-untrusted --no-network --arch #{arch} --repository '#{repository}' " +
    "add --initdb alpine-base alpine-keys && " +
    "test -s '#{test_root}/lib/apk/db/installed' && " +
    "grep -Fqx 'P:alpine-base' '#{test_root}/lib/apk/db/installed' && " +
    "grep -Fqx 'P:alpine-keys' '#{test_root}/lib/apk/db/installed'"
  run_bundle_command(command)
  run_bundle_command("rm -rf '#{test_root}'")
end

private def run_bundle_command(command : String) : Nil
  result = @interaction.execute(command, 300.seconds)
  unless result.success?
    raise "Alpine bundle command failed (exit=#{result.exit_code}): #{command}\n#{result.stderr}\n#{result.stdout}"
  end
end
