task :bgem do
  sh 'bundle exec bgem'
end

task :build do
  sh 'crystal build --no-codegen src/qemu.cr'
end

task :default => [:bgem, :build]
