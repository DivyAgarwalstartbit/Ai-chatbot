require "net/http"
require "json"


module Ai
class OllamaEmbeddingService
def initialize(text)
 @text = text
end



def call
 uri =
  URI(
   "http://localhost:11434/api/embeddings"
  )


 response =
  Net::HTTP.post(

   uri,


   {
    model: "nomic-embed-text",

    prompt: @text

   }.to_json,


   {
    "Content-Type" => "application/json"
   }

  )



 data =
  JSON.parse(
   response.body
  )



 data["embedding"]
end
end
end
