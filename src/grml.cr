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

        report_bundle_progress(progress, "Preparing Alpine offline bundle")
        report_bundle_progress(progress, "Alpine branch: #{branch}")
        report_bundle_progress(progress, "Bundle directory: #{@vm.shared_path}/alpine-bundle")

        report_bundle_stage(1, "Checking GRML architecture", progress) do
          verify_bundle_architecture
        end

        report_bundle_stage(2, "Preparing bundle directory", progress) do
          # Invalidate any previous success marker before rebuilding. A failed repeat
          # must not leave an old manifest describing a partially replaced bundle.
          run_bundle_command(
            "rm -rf #{repository} #{apk_root} #{keys} #{tools} #{bundle}/verify-root && " +
            "rm -f #{bundle}/MANIFEST #{bundle}/SHA256SUMS && " +
            "mkdir -p #{tools} #{keys} #{packages} #{apk_root}"
          )
        end

        report_bundle_stage(3, "Downloading and verifying alpine-chroot-install", progress) do
          run_bundle_command(
            "cd #{tools} && curl -fsSL " +
            "https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/v0.14.0/alpine-chroot-install " +
            "-o alpine-chroot-install"
          )
          run_bundle_command(
            "cd #{tools} && printf '%s  %s\\n' " +
            "ccbf65f85cdc351851f8ad025bb3e65bae4d5b06 alpine-chroot-install | sha1sum -c -"
          )
        end

        report_bundle_stage(4, "Downloading and verifying apk.static", progress) do
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
        end

        report_bundle_stage(5, "Extracting and installing Alpine signing keys", progress) do
          extract_alpine_keys(tools, keys)
          run_bundle_command("mkdir -p #{apk_root}/etc/apk/keys && cp #{keys}/*.rsa.pub #{apk_root}/etc/apk/keys/")
        end

        report_bundle_stage(6, "Fetching Alpine packages from main and community", progress) do
          fetch_alpine_packages(packages, apk_root, tools, mirror, branch)
        end

        report_bundle_stage(7, "Building the local APK repository index", progress) do
          build_local_repository(packages, tools, keys)
        end

        report_bundle_stage(8, "Verifying offline installation", progress) do
          verify_offline_repository(packages, bundle, tools, keys, arch)
        end

        report_bundle_stage(9, "Writing manifest and checksums", progress) do
          write_bundle_manifest(bundle, repository, branch)
        end

        report_bundle_progress(progress, "Prepared Alpine offline bundle in #{@vm.shared_path}/alpine-bundle")
      end

      private def report_bundle_stage(
        index : Int32,
        title : String,
        progress : Proc(String, Nil)?,
        &block : -> Nil
      ) : Nil
        label = "[#{index}/9] #{title}"
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

      private def verify_offline_repository(packages : String, bundle : String, tools : String, keys : String, arch : String) : Nil
        test_root = "#{bundle}/verify-root"
        run_bundle_command("rm -rf #{test_root} && mkdir -p #{test_root}/etc/apk/keys && cp #{keys}/*.rsa.pub #{test_root}/etc/apk/keys/")
        command = "#{tools}/apk.static --root #{test_root} --keys-dir #{test_root}/etc/apk/keys " +
          "--allow-untrusted --no-network --arch #{arch} --repository #{packages} " +
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
          context.puts(GRML::REPL.prepare_alpine_bundle(agent, arguments, progress))
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