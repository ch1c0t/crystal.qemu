def prepare_alpine_bundle(branch : String = "latest-stable") : Nil
  unless branch.matches(/\A[a-zA-Z0-9._-]+\z/)
    raise "Invalid Alpine branch: #{branch.inspect}"
  end

  bundle = "/mnt/shared/alpine-bundle"
  repository = "#{bundle}/repository"
  packages = "#{repository}/packages"
  tools = "#{bundle}/tools"
  keys = "#{bundle}/keys"
  arch = "x86_64"
  mirror = "https://dl-cdn.alpinelinux.org/alpine"

  run_bundle_command("mkdir -p #{tools} #{keys} #{packages} #{repository}/main/#{arch} #{repository}/community/#{arch}")
  verify_bundle_architecture

  run_bundle_command(
    "cd #{tools} && curl -fsSL " +
    "https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/v0.14.0/alpine-chroot-install " +
    "-o alpine-chroot-install"
  )
  run_bundle_command(
    "cd #{tools} && printf '%s  %s\\n' " +
    "ccbf65f85cdc351851f8ad025bb3e65bae4d5b06 alpine-chroot-install | sha1sum -c -"
  )
  run_bundle_command(
    "cd #{tools} && curl -fsSL " +
    "https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v2.14.7/x86_64/apk.static " +
    "-o apk.static"
  )
  run_bundle_command(
    "cd #{tools} && printf '%s  %s\\n' " +
    "bdd044e0fd6cc388c5e571e1093efa5f35f7767cc5aa338b0a2576a429009a62 apk.static | sha256sum -c -"
  )
  run_bundle_command("chmod +x #{tools}/apk.static")
  extract_alpine_keys(tools, keys)
  fetch_alpine_packages(packages, tools, keys, mirror, branch)
  build_local_repository(repository, packages, mirror, branch, arch)
  write_bundle_manifest(bundle, repository, branch)
  Log.info { "Prepared Alpine offline bundle in #{@vm.shared_path}/alpine-bundle" }
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
  command = "awk '/^ALPINE_KEYS=/,/^\\x27$/ { if (NR > 1 && $0 !~ /^ALPINE_KEYS=/ && $0 !~ /^\\x27$/) print }' #{script} | " +
    "while IFS= read -r line; do " +
    "id=\${line%%:*}; content=\${line#*:}; " +
    "[ -n \"\${id}\" ] || continue; " +
    "file=#{keys}/alpine-devel@lists.alpinelinux.org-\${id}.rsa.pub; " +
    "printf '%s\\n' '-----BEGIN PUBLIC KEY-----' > \"\${file}\"; " +
    "printf '%b\\n' \"\${content}\" >> \"\${file}\"; " +
    "printf '%s\\n' '-----END PUBLIC KEY-----' >> \"\${file}\"; done"
  run_bundle_command(command)
end

private def fetch_alpine_packages(packages : String, tools : String, keys : String, mirror : String, branch : String) : Nil
  command = "#{tools}/apk.static --keys-dir #{keys} " +
    "--repository #{mirror}/#{branch}/main " +
    "--repository #{mirror}/#{branch}/community " +
    "fetch --recursive --output #{packages} alpine-base alpine-keys"
  run_bundle_command(command)
end

private def build_local_repository(repository : String, packages : String, mirror : String, branch : String, arch : String) : Nil
  main = "#{repository}/main/#{arch}"
  community = "#{repository}/community/#{arch}"
  run_bundle_command("curl -fsSL #{mirror}/#{branch}/main/#{arch}/APKINDEX.tar.gz -o #{main}/APKINDEX.tar.gz")
  run_bundle_command("curl -fsSL #{mirror}/#{branch}/community/#{arch}/APKINDEX.tar.gz -o #{community}/APKINDEX.tar.gz")
  run_bundle_command("cp #{packages}/*.apk #{main}/ && cp #{packages}/*.apk #{community}/")
end

private def write_bundle_manifest(bundle : String, repository : String, branch : String) : Nil
  command = "cd #{bundle} && " +
    "printf 'format=1\\nalpine_branch=%s\\narchitecture=x86_64\\n' #{branch} > MANIFEST && " +
    "find repository tools -type f ! -name SHA256SUMS -print0 | " +
    "sort -z | xargs -0 sha256sum > SHA256SUMS"
  run_bundle_command(command)
end

private def run_bundle_command(command : String) : Nil
  result = @interaction.execute(command, 300.seconds)
  unless result.success?
    raise "Alpine bundle command failed (exit=#{result.exit_code}): #{command}\\n#{result.stderr}"
  end
end
