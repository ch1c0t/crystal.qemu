require "./qemu"
require "tmux_repl"

module GRML

  class Agent
    module Boot
      def boot : Nil
        navigate_boot_menu
        wait_for_shell
        verify_guest_agent
        configure_console
        verify_shared_directory
      
        Log.info { "GRML shared directory is operational" }
      end
      
      private def navigate_boot_menu : Nil
        Log.info { "Waiting for GRML boot prompt" }
        @interaction.wait_for_text("Press ENTER to boot", region: :bottom_tenth)
        Log.info { "Sending Return to GRML boot prompt" }
        @vm.send_key("ret")
      
        Log.info { "Waiting for GRML key prompt" }
        @interaction.wait_for_text("Press a key", region: :bottom_tenth)
        Log.info { "Sending Return to GRML key prompt" }
        @vm.send_key("ret")
      end
      
      private def wait_for_shell : Nil
        Log.info { "Waiting for GRML shell prompt" }
        @interaction.wait_for_text("root@grml", 180.seconds, :bottom_tenth)
      end
      
      private def verify_guest_agent : Nil
        Log.info { "GRML command line ready; checking QEMU Guest Agent" }
        result = @interaction.execute("printf 'qemu-guest-agent-ok\\n'")
        unless result.success? && result.stdout.strip == "qemu-guest-agent-ok"
          raise "QEMU Guest Agent test failed (exit=#{result.exit_code}, stdout=#{result.stdout.inspect}, stderr=#{result.stderr.inspect})"
        end
        Log.info { "QEMU Guest Agent is operational" }
      end
      
      private def configure_console : Nil
        Log.info { "Setting GRML console font size to 12x24" }
        result = @interaction.execute("sed -i 's|^FONTSIZE=.*|FONTSIZE=\"12x24\"|' /etc/default/console-setup && grep -Fqx 'FONTSIZE=\"12x24\"' /etc/default/console-setup && setupcon")
        unless result.success?
          raise "Could not configure GRML console font size (exit=#{result.exit_code}, stderr=#{result.stderr.inspect})"
        end
        Log.info { "GRML console font size set to 12x24" }
      end
    end
  
    module CreateAlpineImage
      def create_alpine_image(iso_path : String? = nil) : Nil
        raise "Alpine image creation workflow is not implemented yet. Should GRML create Alpine image?"
      end
    end
  
    module PrepareAlpineBundle
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
        arch = "x86_64"
        apk_root = run.apk_root
        mirror = "https://dl-cdn.alpinelinux.org/alpine"
        started_at = Time.monotonic

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
            "printf 'run_id=%s\\nstatus=running\\n' '#{run.run_id}' > '#{bundle}/RUNNING'"
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
            "ccbf65f85cdc351851f8ad025bb3e65bae4d5b06 alpine-chroot-install | sha1sum -c -"
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

        report_bundle_stage(7, "Building the local APK repository index", progress) do
          build_local_repository(packages, tools, keys)
        end

        report_bundle_stage(8, "Checking the local APK repository", progress) do
          inspect_local_repository(bundle, repository, packages)
        end

        report_bundle_stage(9, "Verifying offline installation", progress) do
          verify_offline_repository(repository, bundle, tools, keys, arch)
        end

        report_bundle_stage(10, "Writing manifest, checksums, and completion marker", progress) do
          write_bundle_manifest(bundle, branch, arch, run.run_id)
        end

        report_bundle_stage(11, "Publishing the LATEST bundle pointer", progress) do
          publish_latest_bundle(run)
        end

        elapsed = Time.monotonic - started_at
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
        label = "[#{index}/11] #{title}"
        started_at = Time.monotonic
        report_bundle_progress(progress, "#{label} ...")

        begin
          yield
        rescue ex
          elapsed = Time.monotonic - started_at
          report_bundle_progress(progress, "#{label} FAILED (#{elapsed.total_seconds.round(1)}s)")
          raise "Failed during #{title}: #{ex.message}"
        end

        elapsed = Time.monotonic - started_at
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

      private def build_local_repository(packages : String, tools : String, keys : String) : Nil
        index = "#{packages}/APKINDEX.tar.gz"
        run_bundle_command(
          "cd '#{packages}' && '#{tools}/apk.static' --keys-dir '#{keys}' index --output '#{index}' *.apk"
        )
      end

      private def inspect_local_repository(bundle : String, repository : String, packages : String) : Nil
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

        report_bundle_progress(nil, result.stdout.strip)
      end

      private def verify_offline_repository(repository : String, bundle : String, tools : String, keys : String, arch : String) : Nil
        test_root = "#{bundle}/verify-root"
        run_bundle_command("rm -rf '#{test_root}' && mkdir -p '#{test_root}/etc/apk/keys' && cp '#{keys}'/*.rsa.pub '#{test_root}/etc/apk/keys/'")
        command = "'#{tools}/apk.static' --root '#{test_root}' --keys-dir '#{test_root}/etc/apk/keys' " +
          "--allow-untrusted --no-network --arch #{arch} --repository '#{repository}' " +
          "add --initdb alpine-base alpine-keys"
        run_bundle_command(command)
        run_bundle_command("rm -rf '#{test_root}'")
      end

      private def write_bundle_manifest(bundle : String, branch : String, arch : String, run_id : String) : Nil
        command = "cd '#{bundle}' && " +
          "printf 'format=3\\nrun_id=%s\\nalpine_branch=%s\\narchitecture=%s\\nrepository=repository\\nrepository_architecture=%s\\nindex_signature=unsigned\\ncompletion_marker=COMPLETE\\n' " +
          "'#{run_id}' '#{branch}' '#{arch}' '#{arch}' > MANIFEST && " +
          "find MANIFEST repository tools keys -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS && " +
          "printf 'run_id=%s\\n' '#{run_id}' > COMPLETE && " +
          "rm -f RUNNING"
        run_bundle_command(command)
      end

      private def publish_latest_bundle(run : GRML::AlpineBundleRun) : Nil
        command = "test -f '#{run.directory}/COMPLETE' && " +
          "tmp=$(mktemp '#{run.bundle_root}/.LATEST.XXXXXX') && " +
          "printf '%s\\n' '#{run.latest_pointer_contents}' > \"$tmp\" && " +
          "mv -f \"$tmp\" '#{run.bundle_root}/LATEST'"
        run_bundle_command(command)
      end

      private def run_bundle_command(command : String) : Nil
        result = @interaction.execute(command, 300.seconds)
        unless result.success?
          raise "Alpine bundle command failed (exit=#{result.exit_code}): #{command}\n#{result.stderr}"
        end
      end
    end
  
    module Terminate
      def terminate : Bool
        return true if @terminated
      
        Log.info { "Terminating GRML agent" }
        @terminated = @interaction.terminate
        if @terminated
          Log.info { "GRML agent terminated" }
        else
          Log.error { "GRML agent reported a shutdown failure" }
        end
        @terminated
      end
    end
  
    module VerifySharedDirectory
      def verify_shared_directory : Nil
        token = Random.rand(1_i64..Int64::MAX).to_s
        host_file = File.join(@vm.shared_path, ".qemu-host-check-#{token}")
        guest_host_file = "/mnt/shared/.qemu-host-check-#{token}"
        guest_file = "/mnt/shared/.qemu-guest-check-#{token}"
        File.write(host_file, token)
      
        begin
          verify_guest_mount
          verify_guest_read(guest_host_file, token)
          verify_guest_write(guest_file, token)
          unless File.read(File.join(@vm.shared_path, File.basename(guest_file))) == token
            raise "Guest-created shared file is not visible to the host"
          end
        ensure
          @interaction.execute("unlink #{guest_host_file}")
          @interaction.execute("unlink #{guest_file}")
          File.delete(host_file) if File.exists?(host_file)
        end
      end
      
      private def verify_guest_mount : Nil
        command = "mkdir -p /mnt/shared && (mountpoint -q /mnt/shared || " +
          "mount -t 9p -o trans=virtio,version=9p2000.L shared0 /mnt/shared)"
        result = @interaction.execute(command)
        raise "Could not mount QEMU shared directory at /mnt/shared" unless result.success?
      end
      
      private def verify_guest_read(path : String, expected : String) : Nil
        result = @interaction.execute("cat #{path}")
        unless result.success? && result.stdout.strip == expected
          raise "GRML guest cannot read files from the shared directory"
        end
      end
      
      private def verify_guest_write(path : String, token : String) : Nil
        result = @interaction.execute("printf '%s' #{token} > #{path}")
        raise "GRML guest cannot write to the shared directory" unless result.success?
      end
    end
  
    getter vm : QEMU::VM
    getter interaction : QEMU::Interaction
    
    def initialize(iso_path : String? = nil)
      resolved_iso = QEMU::ISOResolver.resolve("grml", iso_path)
      @vm = QEMU::VM.new(iso_path: resolved_iso)
      Log.info { "Started a QEMU::VM with #{@vm.iso_path}" }
      @interaction = QEMU::Interaction.new(@vm)
      @terminated = false
    end
    
    include Boot
    include VerifySharedDirectory
    include CreateAlpineImage
    include PrepareAlpineBundle
    include Terminate
  end

  class AlpineBundleRun
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
  end

  class REPL
    FOCUS_ENV = "GRML_AGENT_REPL_FOCUS"
    DEFAULT_ALPINE_BRANCH = "latest-stable"

    def self.focus? : Bool
      value = ENV.fetch(FOCUS_ENV, "true").strip.downcase

      case value
      when "1", "true", "yes", "on"
        true
      when "0", "false", "no", "off"
        false
      else
        raise ArgumentError.new("#{FOCUS_ENV} must be a boolean (true/false, yes/no, on/off, or 1/0); got #{value.inspect}")
      end
    end

    def self.alpine_branch(arguments : Array(String)) : String
      if arguments.size > 1
        raise ArgumentError.new("Usage: prepare_alpine_bundle [alpine_branch]")
      end

      branch = arguments.first? || DEFAULT_ALPINE_BRANCH
      unless branch =~ /\A[a-zA-Z0-9._-]+\z/
        raise ArgumentError.new("Invalid Alpine branch: #{branch.inspect}")
      end

      branch
    end

    # Keep this operation on the existing agent. The caller may invoke it
    # repeatedly without creating another VM or reconnecting to the guest.
    def self.prepare_alpine_bundle(
      agent : T,
      arguments : Array(String),
      progress : Proc(String, Nil)? = nil
    ) : String forall T
      branch = alpine_branch(arguments)
      agent.prepare_alpine_bundle(branch, progress)
      "Prepared Alpine offline bundle (branch: #{branch})."
    end

    def self.build_definition(agent : T) : TmuxREPL::Definition forall T
      TmuxREPL.define("grml") do |repl|
        repl.on_command("ocr") do |context, arguments|
          raise ArgumentError.new("Usage: ocr") unless arguments.empty?

          result = agent.interaction.latest_ocr
          if error = result.error
            raise "OCR failed for frame #{result.timestamp}: #{error}"
          end

          if result.text.strip.empty?
            context.puts("(no text recognized)")
          else
            context.write(result.text)
          end
        end

        repl.on_command("prepare_alpine_bundle") do |context, arguments|
          progress = ->(message : String) { context.puts(message) }
          GRML::REPL.prepare_alpine_bundle(agent, arguments, progress)
          nil
        end
      end
    end

    def self.run(agent : Agent) : Nil
      definition = build_definition(agent)
      started = false

      Signal::INT.trap do
        begin
          definition.stop if started
        ensure
          agent.terminate
          exit
        end
      end
      Signal::TERM.trap do
        begin
          definition.stop if started
        ensure
          agent.terminate
          exit
        end
      end

      begin
        focus = focus?
        definition.start(focus: focus)
        started = true

        if focus
          Log.info { "GRML REPL started in session 'grml'." }
        else
          Log.info { "GRML REPL started in session 'grml'; switch to it with: tmux switch-client -t grml" }
        end

        definition.serve
      ensure
        definition.stop if started
      end
    end
  end

  module CLI
    def self.run(arguments : Array(String) = ARGV.dup) : Nil
      args = arguments.dup
      command = args.shift?
    
      case command
      when "boot"
        Act::Boot.new(args).run
      when "tmux"
        Act::Tmux.new(args).run
      when "create_alpine_image"
        Act::CreateAlpineImage.new(args).run
      when "prepare_alpine_bundle"
        Act::PrepareAlpineBundle.new(args).run
      else
        STDERR.puts "Usage: grml.agent boot [--iso PATH] | tmux [--iso PATH] | prepare_alpine_bundle [alpine_branch] | create_alpine_image [alpine_iso_path]"
        exit 1
      end
    end
  
    class Act
      getter arguments : Array(String)
      getter boot_iso_path : String?
      
      def initialize(@arguments : Array(String) = [] of String)
        @boot_iso_path = nil
        validate_arguments
      end
      
      def validate_arguments
      end
      
      def run : Nil
        agent = GRML::Agent.new(@boot_iso_path)
        Signal::INT.trap { agent.terminate && exit }
        Signal::TERM.trap { agent.terminate && exit }
        begin
          agent.boot
          perform(agent)
        ensure
          agent.terminate
        end
      end
      
      protected def perform(agent : GRML::Agent) : Nil
      end
    
      class Boot < Act
        def validate_arguments
          if @arguments.size == 2 && @arguments[0] == "--iso"
            @boot_iso_path = @arguments[1]
          else
            unless @arguments.empty?
              STDERR.puts "Usage: grml.agent boot [--iso PATH]"
              exit 1
            end
          end
        end
        
        protected def perform(agent : GRML::Agent) : Nil
          Log.info { "GRML agent is running. Starting REPL." }
          GRML::REPL.run(agent)
        end
      end
    
      class CreateAlpineImage < Act
        @iso_path : String?
        
        def validate_arguments
          if @arguments.size > 1
            STDERR.puts "Usage: grml.agent create_alpine_image [alpine_iso_path]"
            exit 1
          end
        
          @iso_path = @arguments.first?
        end
        
        protected def perform(agent : GRML::Agent) : Nil
          agent.create_alpine_image(@iso_path)
        end
      end
    
      class PrepareAlpineBundle < Act
        @branch : String = "latest-stable"
        
        def validate_arguments
          if @arguments.size > 1
            STDERR.puts "Usage: grml.agent prepare_alpine_bundle [alpine_branch]"
            exit 1
          end
        
          @branch = @arguments.first? || "latest-stable"
        end
        
        protected def perform(agent : GRML::Agent) : Nil
          agent.prepare_alpine_bundle(@branch)
        end
      end
    
      class Tmux < Act
        def validate_arguments
          if @arguments.size == 2 && @arguments[0] == "--iso"
            @boot_iso_path = @arguments[1]
          else
            unless @arguments.empty?
              STDERR.puts "Usage: grml.agent tmux [--iso PATH]"
              exit 1
            end
          end
        end
        
        protected def perform(agent : GRML::Agent) : Nil
          Log.info { "Starting tmux in the GRML shell" }
          agent.interaction.type("tmux")
          agent.vm.send_key("ret")
          Log.info { "GRML agent is running tmux. Press Ctrl-C to terminate the VM." }
          sleep
        end
      end
    end
  end
end