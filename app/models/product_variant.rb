class ProductVariant < ApplicationRecord
  belongs_to :shop
  belongs_to :product
  has_many :document_chunks,
        as: :source,
        dependent: :destroy
end
