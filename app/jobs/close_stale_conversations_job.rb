# frozen_string_literal: true

class CloseStaleConversationsJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 4.days

  def perform
    threshold = STALE_AFTER.ago

    stale_conversations(threshold).find_each do |conv|
      conv.update_columns(status: "closed", ended_at: Time.current)
      clear_redis(conv.id)
    end
  end

  private

  def stale_conversations(threshold)
    Conversation
      .where(status: "open")
      .where(
        "last_message_at < :t OR (last_message_at IS NULL AND created_at < :t)",
        t: threshold
      )
  end

  def clear_redis(conv_id)
    Rails.cache.delete("ai:ctx:conversation:#{conv_id}")
    Rails.cache.delete("ai:summary:conversation:#{conv_id}")
  rescue => e
    Rails.logger.error("[CloseStaleConversations] Cache error for conv #{conv_id}: #{e.message}")
  end
end
