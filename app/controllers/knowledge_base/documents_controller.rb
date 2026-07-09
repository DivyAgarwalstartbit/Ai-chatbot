# frozen_string_literal: true

class KnowledgeBase::DocumentsController < AuthenticatedController
  DOC_MAX_MB  = { "free" => 0, "starter" => 2,  "pro" => 5  }.freeze

  skip_before_action :verify_authenticity_token, only: %i[create destroy]

  before_action :set_shop_context

  def index
    @documents = current_shop.training_documents
                             .where(document_type: "uploaded_document")
                             .with_attached_file
                             .order(created_at: :desc)
  end

  def create
    plan            = current_shop.plan.presence || "free"
    effective_limit = current_shop.effective_document_limit

    # Free plan: documents not allowed at all
    if effective_limit == 0
      return respond_to do |format|
        format.turbo_stream { render turbo_stream: ts_js("if (typeof showToast === 'function') showToast('Document uploads are not available on the Free plan. Upgrade to Starter or Pro.', true);") }
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1), alert: "Document uploads not available on Free plan." }
      end
    end

    doc_count = current_shop.training_documents.where(document_type: "uploaded_document").count

    # Free/Starter: hard block at limit
    if !current_shop.pro? && doc_count >= effective_limit
      if current_shop.starter?
        cache_key = "limit_email:#{current_shop.id}:document:#{Date.current}"
        unless Rails.cache.exist?(cache_key)
          Rails.cache.write(cache_key, true, expires_in: 1.day)
          LimitReachedMailer.limit_reached(shop: current_shop, resource: :document).deliver_later
        end
      end
      upgrade_msg = plan == "starter" ? "Upgrade to Pro for more documents." : "Upgrade to Starter or Pro."
      return respond_to do |format|
        format.turbo_stream { render turbo_stream: ts_js("if (typeof showToast === 'function') showToast('Document limit reached. Your #{plan.capitalize} plan allows #{effective_limit} documents. #{upgrade_msg}', true);") }
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1), alert: "Document limit reached." }
      end
    end

    file      = document_params[:file]
    max_bytes = DOC_MAX_MB[plan].megabytes

    if file && file.size > max_bytes
      return respond_to do |format|
        format.turbo_stream { render turbo_stream: ts_js("if (typeof showToast === 'function') showToast('File too large. Your #{plan.capitalize} plan allows up to #{DOC_MAX_MB[plan]} MB per document.', true);") }
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1), alert: "File too large." }
      end
    end

    @document = current_shop.training_documents.build(
      document_type:     "uploaded_document",
      title:             file&.original_filename,
      processing_status: "pending"
    )
    @document.file.attach(file)

    if @document.save
      ProcessDocumentJob.perform_later(@document.id)

      # Pro: if doc count now exceeds limit, auto-charge overage
      new_count = current_shop.training_documents.where(document_type: "uploaded_document").count
      if current_shop.overage_eligible? && new_count > current_shop.effective_document_limit
        OverageService.new(shop: current_shop, resource_type: :document).check_and_charge!
      end
      @documents = ordered_documents

      upload_html = render_to_string(partial: "knowledge_base/documents/upload_form",
                                     formats: [ :html ],
                                     locals: { shop_origin: @shop_origin, host: @host, pro: current_shop.pro? })

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
                       id: "document_count_badge", count: @documents.size, label: "file"),
            ts_js("if (typeof showToast === 'function') showToast('Document uploaded');")
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
          turbo_stream.remove("training_document_#{@document.id}"),
          ts_replace("document_actions", "knowledge_base/documents/actions", documents: @documents),
          ts_replace("document_count_badge", "knowledge_base/shared/count_badge",
                     id: "document_count_badge", count: @documents.size, label: "file")
        ]

        if @documents.empty?
          streams << turbo_stream.replace("document_empty_state") {
            '<div id="document_empty_state"><p style="font-size:12px;color:#8c9196;margin:4px 0;">No documents uploaded yet.</p></div>'.html_safe
          }
        end

        streams << ts_js("if (typeof showToast === 'function') showToast('Document deleted');")
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

  def ts_js(js)
    turbo_stream.append("body") { "<script>#{js}</script>".html_safe }
  end
end
