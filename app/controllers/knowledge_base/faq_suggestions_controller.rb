# frozen_string_literal: true

# Handles AI-powered FAQ suggestion generation and import.
#
# Routes:
#   POST /knowledge_base/faq_suggestions/suggest  → gather context, generate, deduplicate
#   POST /knowledge_base/faq_suggestions/import   → save selected suggestions as FAQs
#
# The suggest action renders a Turbo Stream that replaces the suggestion panel
# inside the faq-suggestions-modal with the shared FAQ review UI.
#
# The import action is identical to FaqImportsController#import — it creates
# TrainingDocument records with document_type: "faq".
#
class KnowledgeBase::FaqSuggestionsController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: %i[suggest import]
  before_action :set_shop_context

  # POST /knowledge_base/faq_suggestions/suggest
  def suggest
    result = FaqSuggestionService.new(current_shop).call

    unless result.success?
      return render_suggest_error(result.error)
    end

    if result.suggestions.empty?
      return render_suggest_error(
        "No new FAQ suggestions could be generated. " \
        "All generated FAQs already exist, or there isn't enough content in your knowledge base yet."
      )
    end

    @suggestions = result.suggestions
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  # POST /knowledge_base/faq_suggestions/import
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
    Rails.logger.error("[FaqSuggestionsController] Save failed: #{e.message}")
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

  def parse_import_params
    raw = params.permit(faqs: {})[:faqs] || {}
    raw.values.select { |f| f["selected"] == "1" }
  end

  def render_suggest_error(message)
    @error = message
    respond_to do |format|
      format.turbo_stream { render :suggest_error }
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
