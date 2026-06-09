module Ai
class OrderAgentService
def initialize(shop:, message:)
 @shop = shop

 @message = message
end





def call
 order_number =
  extract_order_number




 unless order_number

  return ask_order_number

 end



 # later:
 # order = Shopify::OrderService.new(
 #   @shop,
 #   order_number
 # ).find



 Ai::ChatGenerationService
 .new(

  message: @message,


  context:
  "
  Customer is asking about order #{order_number}.

  Shopify order lookup integration pending.
  ",



  instructions:
  "
  Tell customer order lookup is being checked.
  Do not create fake order status.
  "

 )
 .call
end

private


def extract_order_number
 match =
 @message.match(
  /#?\d{3,}/
 )


 match &&
 match[0]
 .delete("#")
end



def ask_order_number
 Ai::ChatGenerationService
 .new(

  message: @message,


  instructions:
  "
  Customer wants order information.

  Politely ask for order number.
  "

 )
 .call
end
end
end
