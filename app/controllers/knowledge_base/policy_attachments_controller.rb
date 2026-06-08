# frozen_string_literal: true

# Handles file attachment for shipping_policy and return_policy sections.
# The policy_type is set via route defaults (:shipping_policy or :return_policy).
class KnowledgeBase::PolicyAttachmentsController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: %i[create destroy]

  before_action :set_shop_context
  before_action :set_policy

  def new; end

  def create
    if attachment_params[:file].blank?
      return respond_with_error("Please select a file to upload.")
    end

    @policy.file.attach(attachment_params[:file])

    if @policy.save
      @policy.touch
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    else
      respond_with_error(@policy.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @policy.file.purge
    @policy.reload
    @policy.touch

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  private

  def set_shop_context
    @shop_origin = current_shopify_domain
    @host        = params[:host]
    @policy_type = params[:policy_type]   # set by route defaults
  end

  def set_policy
    @policy = current_shop.training_documents
                          .find_or_initialize_by(document_type: @policy_type)
    @policy.title ||= @policy_type.humanize
    @policy.save! if @policy.new_record?
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
