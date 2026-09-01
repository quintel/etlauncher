# Mounted into etengine/etmodel/my-etm containers only (see compose.yaml). Rails'
# development.rb logs to log/development.log, not STDOUT, so `docker compose logs`
# shows nothing; this reassigns Rails.logger the same way production.rb does.
if Rails.env.development?
  logger = ActiveSupport::Logger.new(STDOUT)
  logger.formatter = ::Logger::Formatter.new
  Rails.logger = ActiveSupport::TaggedLogging.new(logger)
end
