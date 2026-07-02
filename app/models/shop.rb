# frozen_string_literal: true

class Shop < ActiveRecord::Base
  include ShopifyApp::ShopSessionStorage

  has_many :products, dependent: :destroy
  has_many :product_variants, dependent: :destroy
  has_many :tickets, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :training_documents, dependent: :destroy
  has_many :document_chunks, dependent: :destroy
  has_many :overage_bundles, class_name: "ShopOverageBundle", dependent: :destroy
  has_one  :ai_shopper_configuration, dependent: :destroy

  PLANS = {
    "starter" => {
      name:       "Starter",
      price:      ENV.fetch("starter_plan_price"),
      trial_days: ENV.fetch("app_trial_days").to_i
    },
    "pro" => {
      name:       "Pro",
      price:      ENV.fetch("pro_plan_price"),
      trial_days: ENV.fetch("app_trial_days").to_i
    }
  }.freeze

  PLAN_BASE_LIMITS = {
    "free"    => { conversations: 3,  tickets: 2,  faqs: 5,  documents: 0,  products: 10  },
    "starter" => { conversations: 40, tickets: 20, faqs: 10, documents: 3,  products: 100 },
    "pro"     => { conversations: 80, tickets: 50, faqs: 50, documents: 10, products: 500 }
  }.freeze

  # Max messages allowed within a single conversation (nil = unlimited)
  MESSAGES_PER_CONVERSATION = {
    "free"    => 50,
    "starter" => 20,
    "pro"     => 30
  }.freeze

  OVERAGE_BUNDLE        = { conversations: 3, tickets: 2, documents: 5, products: 10, messages_per_conversation: 5 }.freeze
  OVERAGE_BUNDLE_PRICE  = "0.30"
  OVERAGE_CAPPED_AMOUNT = ENV.fetch("overage_capped_amount", "10.00")

  validates :plan, inclusion: { in: PLANS.keys + [ "free" ], allow_nil: true }

  def free?      = plan.nil? || plan == "free"
  def starter?   = plan == "starter"
  def pro?       = plan == "pro"
  def plan_label = PLANS.dig(plan, :name) || "Free"

  def effective_conversation_limit = base_limit(:conversations) + extra_conversations.to_i
  def effective_ticket_limit       = base_limit(:tickets)       + extra_tickets.to_i
  def effective_document_limit     = base_limit(:documents)     + extra_documents.to_i
  def effective_faq_limit          = base_limit(:faqs)
  def effective_product_limit      = base_limit(:products) + extra_products.to_i
  def effective_message_limit
    base = MESSAGES_PER_CONVERSATION[plan.presence || "free"]
    # Only Pro gets extra messages via overage bundles; Free/Starter are fixed hard caps
    return base + extra_messages_per_conversation.to_i if pro?
    base
  end

  def overage_eligible?            = pro? && usage_subscription_id.present?

  after_create_commit :setup_shop
  after_create_commit :assign_free_plan

  def api_version
    ShopifyApp.configuration.api_version
  end

  private

  def base_limit(resource)
    PLAN_BASE_LIMITS.dig(plan.presence || "free", resource) || 0
  end

  def setup_shop
    BulkProductSyncJob.perform_later(id)
    CreateAiMetafieldJob.perform_later(id)
  end

  def assign_free_plan
    update_column(:plan, "free") if plan.nil?
  end
end
