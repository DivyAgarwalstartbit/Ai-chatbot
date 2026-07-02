# frozen_string_literal: true

class ShopOverageBundle < ApplicationRecord
  belongs_to :shop

  validates :resource_type, inclusion: { in: %w[conversation ticket document message] }
  validates :amount, numericality: { greater_than: 0 }
  validates :charged_at, presence: true

  scope :this_month, -> { where(charged_at: Time.current.beginning_of_month..) }
end
