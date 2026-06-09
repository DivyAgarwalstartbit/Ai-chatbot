module Ai
class RouterService
def initialize(
 shop:,
 customer: nil,
 message:,
 intent:,
 memory: ""
)
 @shop = shop

 @customer = customer

 @message = message

 @intent = intent.to_s.downcase

 @memory = memory
end






def call
case @intent


when "product_search",
     "product_detail",
     "product_recommendation"


 Ai::ProductAgentService
 .new(
  shop: @shop,
  message: @message,
  intent: @intent,
  memory: @memory
 )
 .call






when "return_policy",
     "shipping_policy",
     "faq",
     "additional_docs"



 Ai::KnowledgeAgentService
 .new(
  shop: @shop,
  message: @message,
  memory: @memory
 )
 .call







when "order_status"



 Ai::OrderAgentService
 .new(
  shop: @shop,
  customer: @customer,
  message: @message,
  memory: @memory
 )
 .call







else


 general_response


end
end








private








def general_response
Ai::ChatGenerationService
.new(

 message: @message,


 context:
 "
 Previous conversation:

 #{@memory}
 ",


 instructions:
 "
 You are an ecommerce support assistant.

 Rules:

 - Answer politely.
 - Help with products, orders, shipping and returns.
 - Use previous conversation if required.
 - If you don't know, say you don't know.
 "

)
.call
end
end
end
