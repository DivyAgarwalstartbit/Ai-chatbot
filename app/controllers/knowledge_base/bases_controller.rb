# frozen_string_literal: true

class KnowledgeBase::BasesController < AuthenticatedController
  FAQ_LIMITS    = { "free" => 5,   "starter" => 10,  "pro" => 50  }.freeze
  DOC_LIMITS    = { "free" => 0,   "starter" => 3,   "pro" => 10  }.freeze
  DOC_MAX_MB    = { "free" => 0,   "starter" => 2,   "pro" => 5   }.freeze
  FAQ_MAX_WORDS = { "free" => 150, "starter" => 150, "pro" => 500 }.freeze

  def index
    @shop_origin = current_shopify_domain
    @host        = params[:host]
    @pro         = current_shop.pro?
    @free        = current_shop.free?
    plan         = current_shop.plan.presence || "free"

    @faq_limit     = FAQ_LIMITS[plan]
    @faq_max_words = FAQ_MAX_WORDS[plan]
    @doc_limit     = DOC_LIMITS[plan]
    @doc_max_mb    = DOC_MAX_MB[plan]

    @shipping_policy = current_shop.training_documents
                                   .with_attached_file
                                   .find_or_initialize_by(document_type: "shipping_policy")
    @return_policy = current_shop.training_documents
                                 .with_attached_file
                                 .find_or_initialize_by(document_type: "return_policy")
    @faqs = current_shop.training_documents
                        .where(document_type: "faq")
                        .with_attached_file
                        .order(:created_at)
    @new_faq = TrainingDocument.new(document_type: "faq")
    @documents = current_shop.training_documents
                             .where(document_type: "uploaded_document")
                             .with_attached_file
                             .order(created_at: :desc)
  end

  private

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end
end
