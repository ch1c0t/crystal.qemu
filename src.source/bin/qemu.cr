require "../qemu"

vm = QEMU::VM.new(iso_path: "~/Downloads/ISOs/grml-full-2026.09-amd64.iso")
puts vm.display # => ":10"
sleep 3.seconds
