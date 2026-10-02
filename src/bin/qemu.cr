require "./qemu/*"

VERSION = "0.0.0"

case ARGV.size
when 1
  case ARGV[0]
  when "-v", "version", "--version"
    puts VERSION
    exit
  when "-h", "help", "--help"
    print_help
    exit
  end
end

require "../qemu"

vm = QEMU::VM.new(iso_path: "~/Downloads/ISOs/grml-full-2026.09-amd64.iso")
puts vm.display # => ":10"
sleep 3.seconds

# Example 1: Query System Status
# Human alternative was "info status" -> QMP alternative is "query-status"
status_res = vm.execute_qmp("query-status")
puts "Status Data: #{status_res}"
# Access nested types safely: status_res["return"]["status"] => "running"

# Example 2: Gracefully Query Block Devices
block_res = vm.execute_qmp("query-block")
puts "Block Device Structure: #{block_res}"

# Example 3: Commands with Arguments (e.g., Injecting a keystroke)
# QMP allows exact parameter hashes passed directly into execution chains
# vm.execute_qmp("system_wakeup")
