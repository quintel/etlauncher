# Mounted into etengine/etmodel/my-etm containers only (see compose.yaml). Rails'
# development.rb logs to log/development.log, not STDOUT, so `docker compose logs`
# shows nothing; this reassigns the logger the same way production.rb does.
if Rails.env.development?
  logger = ActiveSupport::Logger.new(STDOUT)
  logger.formatter = ::Logger::Formatter.new
  stdout_logger = ActiveSupport::TaggedLogging.new(logger)

  Rails.logger = stdout_logger
  ActionController::Base.logger = stdout_logger
  ActionController::API.logger = stdout_logger
end
