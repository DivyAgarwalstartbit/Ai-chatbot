class Ticket < ApplicationRecord
  belongs_to :shop

  belongs_to :customer, optional: true
end
