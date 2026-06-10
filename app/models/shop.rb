# frozen_string_literal: true

class Shop < ActiveRecord::Base
  include ShopifyApp::ShopSessionStorage

  has_many :products
  has_many :customers
  has_many :conversations
  has_many :tickets
  has_many :training_documents
  has_many :document_chunks
  has_one :ai_shopper_configuration

  PLANS = {
    "starter" => {
      name:       "Starter",
      price:      ENV.fetch("starter_plan_price", "9.99"),
      trial_days: ENV.fetch("app_trial_days", "7").to_i
    },
    "pro" => {
      name:       "Pro",
      price:      ENV.fetch("pro_plan_price", "24.99"),
      trial_days: ENV.fetch("app_trial_days", "7").to_i
    }
  }.freeze

  validates :plan, inclusion: { in: PLANS.keys, allow_nil: true }

  def starter? = plan == "starter"
  def pro?     = plan == "pro"
  def plan_label = PLANS.dig(plan, :name)

    after_create_commit :sync_products


  def api_version
    ShopifyApp.configuration.api_version
  end

  def sync_products
    BulkProductSyncJob.perform_later(id)
  end
end
