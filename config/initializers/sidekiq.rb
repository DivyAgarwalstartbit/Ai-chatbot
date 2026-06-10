Sidekiq.configure_server do |config|
  config.redis = { url: "redis://localhost:6379/0" }

  config.queues = %w[embeddings documents default]
end

Sidekiq.configure_client do |config|
  config.redis = { url: "redis://localhost:6379/0" }
end
