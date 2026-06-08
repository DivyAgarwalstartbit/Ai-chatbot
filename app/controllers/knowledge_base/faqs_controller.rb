# frozen_string_literal: true

class KnowledgeBase::FaqsController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: %i[create update destroy]

  before_action :set_shop_context
  before_action :set_faq, only: %i[show edit update destroy]

  def index
    @faqs = current_shop.training_documents
                        .where(document_type: "faq")
                        .order(:created_at)
    @new_faq = TrainingDocument.new(document_type: "faq")
  end

  def new
    @new_faq = TrainingDocument.new(document_type: "faq")
  end

  def show; end

  def edit; end

  def create
    @faq = current_shop.training_documents.build(faq_params.merge(document_type: "faq"))

    if @faq.save
      @faqs = current_shop.training_documents.where(document_type: "faq").order(:created_at)
      @new_faq = TrainingDocument.new(document_type: "faq")
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    else
      @new_faq = @faq
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_entity }
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    end
  end

  def update
    if @faq.update(faq_params)
      @faqs = current_shop.training_documents.where(document_type: "faq").order(:created_at)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :update, status: :unprocessable_entity }
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    end
  end

  def destroy
    @faq.destroy
    @faqs = current_shop.training_documents.where(document_type: "faq").order(:created_at)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  private

  def set_shop_context
    @shop_origin = current_shopify_domain
    @host = params[:host]
  end

  def set_faq
    @faq = current_shop.training_documents.find(params[:id])
  end

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end

  def faq_params
    params.require(:training_document).permit(:title, :content)
  end
end
