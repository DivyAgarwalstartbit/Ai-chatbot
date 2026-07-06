class ApplicationController < ActionController::Base
  before_action :log_memory_before
after_action :log_memory_after

def log_memory_before
  rss_kb = `ps -o rss= -p #{Process.pid}`.to_i
  Rails.logger.info "[MEMORY] BEFORE #{rss_kb / 1024} MB"
end

def log_memory_after
  rss_kb = `ps -o rss= -p #{Process.pid}`.to_i
  Rails.logger.info "[MEMORY] AFTER #{rss_kb / 1024} MB"
end



  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
