class DocumentChunk < ApplicationRecord
   belongs_to :shop

 belongs_to :source,
 polymorphic: true,
 optional: true


 belongs_to :training_document,
 optional: true


 has_neighbors :embedding
end
