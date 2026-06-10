module Ai
class IntentService
def initialize(
 message:,
 context: {}
)
 @message = message

 @context = context
end




def call
Ai::GroqService.new(
[

 {
  role: "system",

  content:
  "
You classify ecommerce customer intent.

Analyze latest user message first.

Use previous context ONLY when message has references like:
- it
- this
- that
- same one
- above product
- my previous one

Previous context:
#{@context}


Return EXACTLY one:

product_search
product_recommendation
order_status
return_policy
shipping_policy
faq
additional_docs
greeting
general


Rules:

Examples:

'liquid snowboard price?'
=> product_search


'is it available?'
(previous context product)
=> product_search


'suggest gift for brother'
=> product_recommendation


'where is my order?'
=> order_status


'return policy?'
=> return_policy


Return only intent label.
No explanation.
  "

 },


 {
  role: "user",

  content: @message
 }


]
)
.call
.strip
.downcase
end
end
end
