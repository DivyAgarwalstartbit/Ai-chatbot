class Customer < ApplicationRecord
  belongs_to :shop

  has_many :conversations, dependent: :nullify

  def guest?
    shopify_customer_id.nil?
  end

  def logged_in?
    !guest?
  end
end
