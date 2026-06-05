class TrainingDocument < ApplicationRecord
  belongs_to :shop
has_many :document_chunks
end
