# frozen_string_literal: true

# Handles the two-step FAQ import flow:
#
#   Step 1 — POST /knowledge_base/faq_import/extract
#     Accepts pasted text OR an uploaded file.
#     Delegates to FaqImportService (extraction + AI generation).
#     Returns a Turbo Stream that replaces the panel with the FAQ preview.
#
#   Step 2 — POST /knowledge_base/faq_import/import
#     Accepts the merchant-reviewed FAQ list (selected items only).
#     Creates TrainingDocument records (document_type: "faq") and returns
#     a Turbo Stream that appends the new FAQs to the main list.
#
class KnowledgeBase::FaqImportsController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: %i[extract import]
  before_action :set_shop_context

  # GET /knowledge_base/faq_import/new
  def new
  end

  # POST /knowledge_base/faq_import/extract
  def extract
    result = FaqImportService.new(
      text: params.dig(:faq_import, :text).presence,
      file: params.dig(:faq_import, :file).presence
    ).call

    unless result.success?
      return render_extract_error(result.error)
    end

    @faqs = result.faqs
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  # POST /knowledge_base/faq_import/import
  def import
    faq_items = parse_import_params

    if faq_items.empty?
      return render_import_error("Please select at least one FAQ to import.")
    end

    @imported_faqs = faq_items.filter_map do |item|
      question = item["question"].to_s.strip
      answer   = item["answer"].to_s.strip
      next if question.blank? || answer.blank?

      current_shop.training_documents.create!(
        document_type: "faq",
        title:         question,
        content:       answer
      )
    end

    if @imported_faqs.empty?
      return render_import_error("All selected FAQs had blank questions or answers. Nothing was saved.")
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[FaqImportsController] Save failed: #{e.message}")
    render_import_error("Failed to save FAQs: #{e.record.errors.full_messages.to_sentence}")
  end

  private

  def set_shop_context
    @shop_origin = current_shopify_domain
    @host        = params[:host]
  end

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end

  # Params come in as indexed hash: faqs[0][question]=... faqs[0][answer]=...
  def parse_import_params
    raw = params.permit(faqs: {})[:faqs] || {}
    raw.values.select { |f| f["selected"] == "1" }
  end

  def render_extract_error(message)
    @error = message
    respond_to do |format|
      format.turbo_stream { render :extract_error }
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  def render_import_error(message)
    @error = message
    respond_to do |format|
      format.turbo_stream { render :import_error }
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end
end
