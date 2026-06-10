module Ai
class KnowledgeAgentService
def initialize(shop:, message:)
 @shop = shop
 @message = message
end




def call
 chunks =
  search_knowledge



 if chunks.empty?

  return no_information

 end




 Ai::ChatGenerationService
 .new(

  message: @message,


  context:
   chunks
   .map(&:content)
   .join("\n\n"),



  instructions:
  "
  You are answering store policy/support questions.

  Rules:
  - Use only provided store knowledge.
  - Answer return, shipping and FAQ questions.
  - Do not invent policies.
  - If information is unavailable say you don't have that information.
  "

 )
 .call
end







private






def search_knowledge
 embedding =
  Ai::OllamaEmbeddingService
  .new(@message)
  .call




 DocumentChunk
 .where(
   shop_id: @shop.id,
   source_type: "TrainingDocument"
 )
 .nearest_neighbors(
   :embedding,
   embedding,
   distance: "cosine"
 )
 .limit(5)
end






def no_information
 Ai::ChatGenerationService
 .new(

  message: @message,


  instructions:
  "
  Tell customer politely that store information is not available.
  Ask them to contact support if needed.
  "

 )
 .call
end
end
end
