module Ai
class MemoryService
RECENT_LIMIT = 6

SUMMARY_AFTER = 20


def initialize(
 shop:,
 customer:,
 session_id:
)
 @conversation =
  Conversation
  .find_or_create_by!(

   shop: shop,

   customer: customer,

   session_id: session_id

  ) do |c|
    c.started_at = Time.current
  end
end


# ==========================
# READ CONTEXT
# ==========================


def context
<<~TEXT

Conversation Summary:

#{summary}


Recent Messages:

#{recent_messages}


TEXT
end


# ==========================
# SAVE MESSAGE
# ==========================


def add(
 role:,
 content:
)
return if content.blank?



@conversation
.messages
.create!(

 role: role,

 content: content

)

schedule_summary
end


def set_context(key, value)
 redis.hset(
  context_key,
  key,
  value
 )

 redis.expire(
  context_key,
  7.days
 )
end

def get_context
 redis.hgetall(
  context_key
 )
end


def context_key
 "ai:ctx:conversation:#{@conversation.id}"
end


private

def recent_messages
 @conversation
 .messages
 .order(created_at: :desc)
 .limit(RECENT_LIMIT)
 .reverse
 .map do |m|
 "#{m.role}: #{m.content}"
 end
 .join("\n")
end


def summary
 redis.get(
  summary_key
 )
end

def schedule_summary
count =
 @conversation
 .messages
 .count

return if count < SUMMARY_AFTER

# every 5 messages update summary

return unless count % 5 == 0


Ai::MemorySummaryJob
.perform_later(

 @conversation.id

)
end


def redis
@redis ||=
 Redis.new(
  url: ENV["REDIS_URL"]
 )
end


def summary_key
"ai:summary:conversation:#{@conversation.id}"
end
end
end
