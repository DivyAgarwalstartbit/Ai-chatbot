module Ai
class MemorySummaryJob < ApplicationJob
queue_as :default

def perform(conversation_id)
conversation =
 Conversation
 .find(
  conversation_id
 )

messages =
 conversation
 .messages
 .order(:created_at)
 .limit(
  [
   conversation.messages.count - 6,
   0
  ].max
 )

return if messages.empty?

old_summary =
 redis.get(
  redis_key(conversation.id)
 )

text =
messages.map do |m|
"#{m.role}: #{m.content}"
end.join("\n")

summary =

Ai::ChatGenerationService
.new(

 message:

<<~TEXT

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

)
.call


redis.set(
 redis_key(conversation.id),

 summary,

 ex: 7.days

)
end


private

def redis
@redis ||=
 Redis.new(
 url: ENV["REDIS_URL"]
)
end


def redis_key(id)
"ai:summary:conversation:#{id}"
end
end
end
