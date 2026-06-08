# frozen_string_literal: true

class KnowledgeBase::DocumentsController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: %i[create destroy]

  before_action :set_shop_context

  def index
    @documents = current_shop.training_documents
                             .where(document_type: "uploaded_document")
                             .with_attached_file
                             .order(created_at: :desc)
  end

  def create
    @document = current_shop.training_documents.build(
      document_type:     "uploaded_document",
      title:             document_params[:file]&.original_filename,
      processing_status: "pending"
    )
    @document.file.attach(document_params[:file])

    if @document.save
      # Enqueue text extraction + chunking pipeline.
      # ProcessDocumentJob: downloads file → extracts text → saves content
      # → TrainingDocument#after_save fires → DocumentChunkJob → ChunkDocumentService
      ProcessDocumentJob.perform_later(@document.id)

      @documents = ordered_documents
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_entity }
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    end
  end

  def destroy
    @document = current_shop.training_documents
                            .where(document_type: "uploaded_document")
                            .find(params[:id])
    @document.file.purge
    @document.destroy

    @documents = ordered_documents
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

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end

  def ordered_documents
    current_shop.training_documents
                .where(document_type: "uploaded_document")
                .with_attached_file
                .order(created_at: :desc)
  end

  def document_params
    params.permit(:file)
  end
end
