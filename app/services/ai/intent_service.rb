module Ai
class IntentService
def initialize(message)
 @message = message
end



def call
 messages = [

  {
   role: "system",
   content: prompt
  },


  {
   role: "user",
   content: @message
  }

 ]


 response =
 Ai::GroqService
 .new(messages)
 .call



 JSON.parse(response)
end
private



def prompt
<<~TEXT

You are an intent classification engine for a Shopify store.

Your task is to classify the customer's message into exactly ONE intent.

Return ONLY valid JSON.

Available intents:

* PRODUCT_SEARCH

  * Customer is looking for products, categories, recommendations, alternatives, or browsing.
  * Examples:

    * "Show me snowboards"
    * "Do you have Burton boards?"
    * "Best snowboard for beginners"

* PRODUCT_DETAIL

  * Customer wants information about a specific product.
  * Examples:

    * "Tell me about the Burton Custom"
    * "What are the specs?"
    * "Is this board good for powder?"

* RETURN_POLICY

  * Customer asks about returns, refunds, exchanges, damaged items, return windows, or return eligibility.
  * Examples:

    * "Can I return my order?"
    * "What's your refund policy?"

* SHIPPING_POLICY

  * Customer asks about shipping, delivery times, shipping costs, tracking, international shipping, or carriers.
  * Examples:

    * "How long does shipping take?"
    * "Do you ship internationally?"

* ORDER_STATUS

  * Customer asks about an existing order.
  * Examples:

    * "Where is my order?"
    * "Track my package"
    * "Order #1234 status"

* FAQ

  * Customer asks store-related questions not covered above.
  * Examples:

    * "Do you offer gift cards?"
    * "What payment methods do you accept?"
    * "Do you have a physical store?"

* GENERAL

  * Greetings, thank you messages, small talk, unclear requests, or anything that does not clearly fit another intent.
  * Examples:

    * "Hi"
    * "Thanks"
    * "Can you help me?"

Rules:

* Choose exactly one intent.
* Use the highest-confidence matching intent.
* Confidence must be a number between 0 and 1.
* Return ONLY JSON.
* Do not include explanations.
* Do not include markdown.
* Do not include additional fields.

Response format:

{
"intent": "",
"confidence": 0.0
}

TEXT
end
end
end
