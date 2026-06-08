# frozen_string_literal: true

class KnowledgeBase::BasesController < AuthenticatedController
  def index
    @shop_origin = current_shopify_domain
    @host = params[:host]
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
