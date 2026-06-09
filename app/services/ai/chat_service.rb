module Ai
class ChatService
def initialize(
 shop:,
 message:
)
 @shop = shop
 @message = message
end





def call
 # Step 1: detect intent

 intent_data =
  Ai::IntentService
  .new(
    @message
  )
  .call




 Rails.logger.info(
  "========= AI INTENT ========="
 )

 Rails.logger.info(
  intent_data
 )

 Rails.logger.info(
  "============================="
 )


 # Step 2: send to router

 Ai::RouterService
 .new(

  shop: @shop,


  message: @message,


  intent_data: intent_data

 )
 .call
end
end
end
