# config/initializers/langfuse.rb

require "langfuse"

Langfuse.configure do |config|
  # ------------------------------------------------------------------
  # Authentication
  # ------------------------------------------------------------------
  config.public_key = ENV.fetch("LANGFUSE_PUBLIC_KEY")
  config.secret_key = ENV.fetch("LANGFUSE_SECRET_KEY")

  # ------------------------------------------------------------------
  # Langfuse Host
  #
  # EU Cloud      : https://cloud.langfuse.com
  # US Cloud      : https://us.cloud.langfuse.com
  # Self Hosted   : https://langfuse.yourdomain.com
  # ------------------------------------------------------------------
  config.host = ENV.fetch(
    "LANGFUSE_HOST",
    "https://cloud.langfuse.com"
  )

  # ------------------------------------------------------------------
  # Performance
  # ------------------------------------------------------------------
  config.batch_size      = ENV.fetch("LANGFUSE_BATCH_SIZE", 20).to_i
  config.flush_interval  = ENV.fetch("LANGFUSE_FLUSH_INTERVAL", 30).to_i
  config.shutdown_timeout = ENV.fetch("LANGFUSE_SHUTDOWN_TIMEOUT", 5).to_i

  # ------------------------------------------------------------------
  # Development Logging
  # ------------------------------------------------------------------
  config.debug = Rails.env.development?

  # Leave enabled unless you plan to flush manually.
  config.disable_at_exit_hook = false
end

Rails.logger.info("[Langfuse] Initialized") if Rails.env.development?
