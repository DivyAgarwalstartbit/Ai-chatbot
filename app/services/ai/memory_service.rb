module Ai
class MemoryService
LIMIT = 10


def initialize(
 shop:,
 session_id:
)
 @shop = shop
 @session_id = session_id
end



def history
 ChatMessage
 .where(
  shop_id: @shop.id,
  session_id: @session_id
 )
 .order(
  created_at: :desc
 )
 .limit(LIMIT)
 .reverse
 .map do |msg|
 "#{msg.role}: #{msg.content}"
 end
 .join("\n")
end


def save_user(message)
 save(
  "user",
  message
 )
end

def save_assistant(message)
 save(
  "assistant",
  message
 )
end

private



def save(role, message)
 ChatMessage.create!(

  shop: @shop,

  session_id: @session_id,

  role: role,

  content: message

 )
end
end
end
