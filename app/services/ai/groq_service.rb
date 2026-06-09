require "net/http"
require "json"


module Ai
class GroqService
def initialize(messages)
 @messages = messages
end



def call
 uri =
 URI(
  "https://api.groq.com/openai/v1/chat/completions"
 )


 response =
 Net::HTTP.post(

  uri,


  {
   model: "llama-3.1-8b-instant",

   messages: @messages,

   temperature: 1

  }.to_json,


  {
   "Authorization" =>
    "Bearer #{ENV['GROQ_API_KEY']}",

   "Content-Type" =>
    "application/json"
  }

 )



 puts "===================="
 puts response.code
 puts response.body
 puts "===================="



 data =
 JSON.parse(response.body)



 data.dig(
  "choices",
  0,
  "message",
  "content"
 )
end
end
end
