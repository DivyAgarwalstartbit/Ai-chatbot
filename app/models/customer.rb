class Customer < ApplicationRecord
   belongs_to :shop

  has_many :conversations, dependent: :nullify
end
