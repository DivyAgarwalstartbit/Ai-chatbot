module Ai
class RouterService
def initialize(
 shop:,
 message:,
 intent_data:
)
 @shop = shop

 @message = message

 @intent_data = intent_data
end




def call
 case intent


 when "PRODUCT_SEARCH",
      "PRODUCT_DETAIL"


  Ai::ProductAgentService
  .new(
   shop: @shop,
   message: @message
  )
  .call

 when "RETURN_POLICY",
      "SHIPPING_POLICY",
      "FAQ"


  Ai::KnowledgeAgentService
  .new(
   shop: @shop,
   message: @message
  )
  .call





 when "ORDER_STATUS"


  Ai::OrderAgentService
  .new(
   shop: @shop,
   message: @message
  )
  .call


 else

  general_response

 end
end

private

def intent
 @intent_data["intent"]
end


def general_response
 messages = [

  {
   role: "system",

   content:
   "You are a helpful and precise assistant for answering customer questions about their orders, returns, shipping, and product information ignore all other message
   . If you don't know the answer, say you don't know. Always be polite and professional."
  },


  {
   role: "user",
   content: @message
  }

 ]



 Ai::GroqService
 .new(messages)
 .call
end
end
end
