def prepare_alpine_bundle(branch : String = "latest-stable") : Nil
  unless branch =~ /\A[a-zA-Z0-9._-]+\z/
    raise "Invalid Alpine branch: #{branch.inspect}"
  end

  bundle = "/mnt/shared/alpine-bundle"
  repository = "#{bundle}/repository"
  tools = "#{bundle}/tools"
  keys = "#{bundle}/keys"
  arch = "x86_64"
  packages = "#{repository}/#{arch}"
  apk_root = "#{bundle}/apk-root"
  mirror = "https://dl-cdn.alpinelinux.org/alpine"

  verify_bundle_architecture
  run_bundle_command("rm -rf #{repository} #{apk_root} #{keys} #{tools} && mkdir -p #{tools} #{keys} #{packages} #{apk_root}")
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
  run_bundle_command("mkdir -p #{apk_root}/etc/apk/keys && cp #{keys}/*.rsa.pub #{apk_root}/etc/apk/keys/")
  fetch_alpine_packages(packages, apk_root, tools, mirror, branch)
  build_local_repository(packages, tools, keys)
  verify_offline_repository(repository, bundle, tools, keys, arch)
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

private def fetch_alpine_packages(packages : String, apk_root : String, tools : String, mirror : String, branch : String) : Nil
  command = "#{tools}/apk.static --root #{apk_root} --keys-dir #{apk_root}/etc/apk/keys --no-cache --arch x86_64 " +
    "--repository #{mirror}/#{branch}/main " +
    "--repository #{mirror}/#{branch}/community " +
    "fetch --recursive --output #{packages} alpine-base alpine-keys"
  run_bundle_command(command)
end

private def build_local_repository(packages : String, tools : String, keys : String) : Nil
  index = "#{packages}/APKINDEX.tar.gz"
  run_bundle_command(
    "cd #{packages} && #{tools}/apk.static --keys-dir #{keys} index --output #{index} *.apk"
  )
end

private def verify_offline_repository(repository : String, bundle : String, tools : String, keys : String, arch : String) : Nil
  test_root = "#{bundle}/verify-root"
  run_bundle_command("rm -rf #{test_root} && mkdir -p #{test_root}/etc/apk/keys && cp #{keys}/*.rsa.pub #{test_root}/etc/apk/keys/")
  command = "#{tools}/apk.static --root #{test_root} --keys-dir #{test_root}/etc/apk/keys " +
    "--allow-untrusted --no-network --arch #{arch} --repository #{repository} " +
    "add --initdb alpine-base alpine-keys"
  run_bundle_command(command)
  run_bundle_command("rm -rf #{test_root}")
end

private def write_bundle_manifest(bundle : String, repository : String, branch : String) : Nil
  command = "cd #{bundle} && " +
    "printf 'format=2\\nalpine_branch=%s\\narchitecture=x86_64\\nrepository=repository/x86_64\\nindex_signature=unsigned\\n' #{branch} > MANIFEST && " +
    "find repository tools keys -type f ! -name SHA256SUMS -print0 | " +
    "sort -z | xargs -0 sha256sum > SHA256SUMS"
  run_bundle_command(command)
end

private def run_bundle_command(command : String) : Nil
  result = @interaction.execute(command, 300.seconds)
  unless result.success?
    raise "Alpine bundle command failed (exit=#{result.exit_code}): #{command}\\n#{result.stderr}"
  end
end
