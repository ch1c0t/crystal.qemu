require "log"

process_name = PROGRAM_NAME.split('/').last

log_level = case ENV.fetch("XEPHYR_LOG_LEVEL", "INFO").upcase
            when "TRACE" then Log::Severity::Trace
            when "DEBUG" then Log::Severity::Debug
            when "INFO"  then Log::Severity::Info
            when "WARN"  then Log::Severity::Warn
            when "ERROR" then Log::Severity::Error
            when "FATAL" then Log::Severity::Fatal
            else
              STDERR.puts "Invalid XEPHYR_LOG_LEVEL; using INFO"
              Log::Severity::Info
            end

formatter = Log::Formatter.new do |entry, io|
  io << "[" << process_name << "] "
  Log::ShortFormat.format(entry, io)
end
log_backend = Log::IOBackend.new(STDERR, formatter: formatter)

Log.setup do |config|
  config.bind "*", log_level, log_backend
  config.bind "amqp.*", Log::Severity::Warn, log_backend
end
