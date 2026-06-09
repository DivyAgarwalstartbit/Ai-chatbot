module Ai
class ChatService
  def initialize(
 shop:,
 customer:,
 session_id:,
 message:
)
 @shop = shop

 @customer = customer

 @session_id = session_id

 @message = message
end


def call
 memory =
  Ai::MemoryService.new(
   shop: @shop,
   customer: @customer,
   session_id: @session_id
  )

 # save user msg
 memory.add(
  role: "user",
  content: @message
 )

 # intent ONLY current message

 intent =
Ai::IntentService.new(
 message: @message,
 context: memory.get_context
).call



 Rails.logger.info(
  "INTENT => #{intent}"
 )

 # memory only for answering

 response =
 Ai::RouterService
 .new(

  shop: @shop,

  customer: @customer,

  message: @message,

  intent: intent,

  memory: memory

 )
 .call


 memory.add(
  role: "assistant",
  content: response
 )

 memory.set_context(
 "last_intent",
 intent
)

 response
end
end
end
