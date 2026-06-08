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
      ProcessDocumentJob.perform_later(@document.id)
      @documents = ordered_documents

      upload_html = render_to_string(partial: "knowledge_base/documents/upload_form",
                                     formats: [ :html ],
                                     locals: { shop_origin: @shop_origin, host: @host })

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            ts_prepend("document_list", "knowledge_base/documents/document",
                       document: @document, shop_origin: @shop_origin, host: @host),
            turbo_stream.replace("document_upload_form") {
              "<turbo-frame id=\"document_upload_form\">#{upload_html}</turbo-frame>".html_safe
            },
            ts_replace("document_actions", "knowledge_base/documents/actions", documents: @documents),
            turbo_stream.replace("document_empty_state") { "" },
            ts_replace("document_count_badge", "knowledge_base/shared/count_badge",
                       id: "document_count_badge", count: @documents.size, label: "file")
          ]
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: [] }
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
      format.turbo_stream do
        streams = [
          turbo_stream.remove(dom_id(@document)),
          ts_replace("document_actions", "knowledge_base/documents/actions", documents: @documents),
          ts_replace("document_count_badge", "knowledge_base/shared/count_badge",
                     id: "document_count_badge", count: @documents.size, label: "file")
        ]

        if @documents.empty?
          streams << turbo_stream.replace("document_empty_state") {
            '<div id="document_empty_state"><p style="font-size:12px;color:#8c9196;margin:4px 0;">No documents uploaded yet.</p></div>'.html_safe
          }
        end

        render turbo_stream: streams
      end
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

  def ts_replace(dom_id, partial, locals = {})
    html = render_to_string(partial: partial, locals: locals, formats: [ :html ])
    turbo_stream.replace(dom_id) { html.html_safe }
  end

  def ts_prepend(dom_id, partial, locals = {})
    html = render_to_string(partial: partial, locals: locals, formats: [ :html ])
    turbo_stream.prepend(dom_id) { html.html_safe }
  end
end
