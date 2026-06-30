class Conversation < ApplicationRecord
  belongs_to :shop

  belongs_to :customer, optional: true

  has_many :messages, dependent: :destroy
  has_many :tickets,  dependent: :nullify
end
