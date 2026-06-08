# frozen_string_literal: true

# Handles file attachment for individual FAQ entries.
class KnowledgeBase::FaqAttachmentsController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: %i[create destroy]

  before_action :set_shop_context
  before_action :set_faq

  def new; end

  def create
    if attachment_params[:file].blank?
      return respond_with_error("Please select a file to upload.")
    end

    @faq.file.attach(attachment_params[:file])

    if @faq.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    else
      respond_with_error(@faq.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @faq.file.purge
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  private

  def set_shop_context
    @shop_origin = current_shopify_domain
    @host        = params[:host]
  end

  def set_faq
    @faq = current_shop.training_documents
                       .where(document_type: "faq")
                       .find(params[:faq_id])
  end

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end

  def attachment_params
    params.require(:attachment).permit(:file)
  end

  def respond_with_error(message)
    @error = message
    respond_to do |format|
      format.turbo_stream { render :error, status: :unprocessable_entity }
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1), alert: message }
    end
  end
end
