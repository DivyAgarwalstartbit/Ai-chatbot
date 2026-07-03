class MemorySummaryJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find(conversation_id)

    messages = conversation.messages
      .order(:created_at)
      .limit([ conversation.messages.count - 6, 0 ].max)

    return if messages.empty?

    old_summary = Rails.cache.read(cache_key(conversation.id))

    text = messages.map { |m| "#{m.role}: #{m.content}" }.join("\n")

    summary = Ai::ChatGenerationService.new(
      message: <<~TEXT
        Update conversation memory.

        Existing summary:

        #{old_summary}

        New messages:

        #{text}

        Rules:

        - Keep product names customer discussed
        - Keep variants/colors/sizes
        - Keep order numbers
        - Keep unresolved issues
        - Remove greetings
        - Keep under 5 bullet points
      TEXT
    ).call

    Rails.cache.write(cache_key(conversation.id), summary, expires_in: 7.days)
  end

  private

  def cache_key(id)
    "ai:summary:conversation:#{id}"
  end
end
