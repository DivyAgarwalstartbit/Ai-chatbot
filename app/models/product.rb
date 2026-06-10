class Product < ApplicationRecord
  belongs_to :shop

   validates :shopify_product_id,
            presence: true,
            uniqueness: {
              scope: :shop_id
            }

      has_many :product_variants

       has_many :document_chunks,
        as: :source,
        dependent: :destroy
end
