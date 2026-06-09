# frozen_string_literal: true

# Handles FAQ CRUD, bulk import (extract + import), AI suggestions, and FAQ attachments.
class KnowledgeBase::FaqsController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: %i[create update destroy extract import suggest suggest_import create_attachment destroy_attachment]

  before_action :set_shop_context
  before_action :set_faq, only: %i[show edit update destroy]
  before_action :set_faq_for_attachment, only: %i[new_attachment create_attachment destroy_attachment]

  # ── CRUD ─────────────────────────────────────────────────────────────────────

  def index
    @faqs    = ordered_faqs
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
      @faqs    = ordered_faqs
      @new_faq = TrainingDocument.new(document_type: "faq")
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            ts_append("faq_list", "knowledge_base/faqs/faq",
                      faq: @faq, shop_origin: @shop_origin, host: @host),
            turbo_stream.replace("faq_form_error") { empty_div("faq_form_error", "data-modal-target": "error") },
            turbo_stream.replace("faq_empty_state") { empty_div("faq_empty_state") },
            ts_replace("faq_count_badge", "knowledge_base/shared/count_badge",
                       id: "faq_count_badge", count: @faqs.size, label: "FAQ"),
            ts_js(<<~JS)
              (function() {
                var modal = document.getElementById('faq-form-modal');
                if (modal && typeof modal.hideOverlay === 'function') { modal.hideOverlay(); }
              })();
            JS
          ]
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    else
      @new_faq = @faq
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: ts_replace("faq_form_error", "knowledge_base/faqs/form_error",
                                          title: "Could not save FAQ",
                                          messages: @faq.errors.full_messages)
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    end
  end

  def update
    if @faq.update(faq_params)
      @faqs = ordered_faqs
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            ts_replace(dom_id(@faq), "knowledge_base/faqs/faq",
                       faq: @faq, shop_origin: @shop_origin, host: @host),
            turbo_stream.replace("faq_form_error") { empty_div("faq_form_error", "data-modal-target": "error") },
            ts_js(<<~JS)
              (function() {
                var modal = document.getElementById('faq-form-modal');
                if (modal && typeof modal.hideOverlay === 'function') { modal.hideOverlay(); }
              })();
            JS
          ]
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: ts_replace("faq_form_error", "knowledge_base/faqs/form_error",
                                          title: "Could not update FAQ",
                                          messages: @faq.errors.full_messages)
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    end
  end

  def destroy
    @faq.destroy
    @faqs = ordered_faqs
    respond_to do |format|
      format.turbo_stream do
        streams = [ turbo_stream.remove(dom_id(@faq)) ]

        if @faqs.empty?
          streams << turbo_stream.replace("faq_empty_state") {
            '<div id="faq_empty_state"><p style="font-size:12px;color:#8c9196;margin:4px 0;">No FAQs yet. Click <strong>Add FAQ</strong> or <strong>Import FAQs</strong> to get started.</p></div>'.html_safe
          }
        end

        streams << ts_replace("faq_count_badge", "knowledge_base/shared/count_badge",
                               id: "faq_count_badge", count: @faqs.size, label: "FAQ")
        render turbo_stream: streams
      end
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  # ── Import (two-step: extract → import) ──────────────────────────────────────

  def import_panel
  end

  def extract
    result = FaqImportService.new(
      text: params.dig(:faq_import, :text).presence,
      file: params.dig(:faq_import, :file).presence
    ).call

    unless result.success?
      return respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            ts_replace("faq_import_error", "knowledge_base/shared/error_banner",
                       id: "faq_import_error", title: "Could not generate FAQs",
                       messages: [ result.error ]),
            ts_js(<<~JS)
              var el = document.querySelector('[data-controller~="faq-import"]');
              if (el && el._stimulusControllers) {
                var ctrl = Object.values(el._stimulusControllers).find(function(c) { return c.identifier === "faq-import"; });
                if (ctrl && typeof ctrl.stopLoading === "function") { ctrl.stopLoading(); return; }
              }
              var loading = document.querySelector('[data-faq-import-target~="loadingIndicator"]');
              if (loading) loading.style.display = "none";
              document.querySelectorAll('[data-faq-import-target~="generateBtn"], [data-faq-import-target~="uploadBtn"]').forEach(function(btn) { btn.removeAttribute("disabled"); });
            JS
          ]
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    end

    @faqs = result.faqs
    review_html = render_to_string(partial: "knowledge_base/faqs/review_panel", formats: [ :html ], locals: {
      items: @faqs,
      form_url: import_knowledge_base_faqs_path(shop: @shop_origin, host: @host, embedded: 1),
      mode: :import,
      title: "Review Generated FAQs",
      description: "#{@faqs.size} FAQ#{@faqs.size == 1 ? '' : 's'} generated. Select the ones to save, edit any text, then click Import selected.",
      panel_controller: "faq-import",
      list_id: "faq_preview_list",
      error_id: "faq_import_result_error",
      selected_count_id: "faq_selected_count",
      import_button_id: "import_selected_btn",
      shop_origin: @shop_origin,
      host: @host
    })

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("faq_import_panel") {
          "<turbo-frame id=\"faq_import_panel\">#{review_html}</turbo-frame>".html_safe
        }
      end
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  def import
    faq_items = parse_faq_params

    if faq_items.empty?
      return respond_to do |format|
        format.turbo_stream do
          render turbo_stream: ts_replace("faq_import_result_error", "knowledge_base/shared/error_banner",
                                          id: "faq_import_result_error", title: "Import failed",
                                          messages: [ "Please select at least one FAQ to import." ])
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    end

    @imported_faqs = save_faq_items(faq_items, "faq_import")
    return if @imported_faqs.nil?

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: import_success_streams(
          "faq_import_panel", "knowledge_base/faqs/import_panel",
          "faq-import-modal", "faq_import_success_banner",
          "#{@imported_faqs.size} FAQ#{@imported_faqs.size == 1 ? '' : 's'} imported"
        )
      end
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  # ── AI Suggestions ────────────────────────────────────────────────────────────

  def suggestions_panel
  end

  def suggest
    result = Ai::FaqGenerationService.for_shop(current_shop).call

    error_msg = if !result.success?
      result.error
    elsif result.faqs.empty?
      "No new FAQ suggestions could be generated. All generated FAQs already exist, or there isn't enough content in your knowledge base yet."
    end

    if error_msg
      return respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            ts_replace("faq_suggestion_error", "knowledge_base/shared/error_banner",
                       id: "faq_suggestion_error", title: "Could not generate suggestions",
                       messages: [ error_msg ]),
            ts_js(<<~JS)
              var loading = document.getElementById('faq_suggestion_loading');
              if (loading) loading.style.display = 'none';
              var btn = document.getElementById('faq_suggest_btn');
              if (btn) { btn.removeAttribute('loading'); btn.removeAttribute('disabled'); }
            JS
          ]
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    end

    @suggestions = result.faqs
    review_html = render_to_string(partial: "knowledge_base/faqs/review_panel", formats: [ :html ], locals: {
      items: @suggestions,
      form_url: suggest_import_knowledge_base_faqs_path(shop: @shop_origin, host: @host, embedded: 1),
      mode: :suggestions,
      title: "Suggested FAQs",
      description: "#{@suggestions.size} suggestion#{@suggestions.size == 1 ? '' : 's'} generated from your knowledge base. Duplicates of existing FAQs have been removed.",
      panel_controller: "faq-suggestions",
      list_id: "faq_suggestion_list",
      error_id: "faq_suggestion_import_error",
      selected_count_id: "suggest_selected_count",
      import_button_id: "suggest_import_btn",
      shop_origin: @shop_origin,
      host: @host
    })

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("faq_suggestion_panel") {
          "<turbo-frame id=\"faq_suggestion_panel\">#{review_html}</turbo-frame>".html_safe
        }
      end
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  def suggest_import
    faq_items = parse_faq_params

    if faq_items.empty?
      return respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            ts_replace("faq_suggestion_import_error", "knowledge_base/shared/error_banner",
                       id: "faq_suggestion_import_error", title: "Import failed",
                       messages: [ "Please select at least one FAQ to import." ]),
            ts_js(<<~JS)
              var btn = document.getElementById('suggest_import_btn');
              if (btn) { btn.removeAttribute('loading'); btn.removeAttribute('disabled'); }
            JS
          ]
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    end

    @imported_faqs = save_faq_items(faq_items, "suggest_import")
    return if @imported_faqs.nil?

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: import_success_streams(
          "faq_suggestion_panel", "knowledge_base/faqs/suggestion_panel",
          "faq-suggestions-modal", "faq_suggestion_success_banner",
          "#{@imported_faqs.size} FAQ#{@imported_faqs.size == 1 ? '' : 's'} added from suggestions"
        )
      end
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  # ── Attachments ───────────────────────────────────────────────────────────────

  def new_attachment
  end

  def create_attachment
    if attachment_params[:file].blank?
      return respond_to do |format|
        format.turbo_stream do
          render turbo_stream: ts_replace(
            "faq_attachment_#{@faq_for_attachment.id}_error",
            "knowledge_base/shared/error_banner",
            id: "faq_attachment_#{@faq_for_attachment.id}_error",
            title: nil, messages: [ "Please select a file to upload." ]
          )
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    end

    @faq_for_attachment.file.attach(attachment_params[:file])

    if @faq_for_attachment.save
      @faq = @faq_for_attachment
      attached_html = render_to_string(partial: "knowledge_base/faqs/attached_file",
                                       formats: [ :html ],
                                       locals: { faq: @faq, frame_id: "faq_attachment_#{@faq.id}",
                                                 shop_origin: @shop_origin, host: @host })
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("faq_attachment_#{@faq.id}") {
            "<turbo-frame id=\"faq_attachment_#{@faq.id}\">#{attached_html}</turbo-frame>".html_safe
          }
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: ts_replace(
            "faq_attachment_#{@faq_for_attachment.id}_error",
            "knowledge_base/shared/error_banner",
            id: "faq_attachment_#{@faq_for_attachment.id}_error",
            title: nil, messages: [ @faq_for_attachment.errors.full_messages.to_sentence ]
          )
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    end
  end

  def destroy_attachment
    @faq_for_attachment.file.purge
    @faq = @faq_for_attachment
    upload_html = render_to_string(partial: "knowledge_base/faqs/upload_form",
                                   formats: [ :html ],
                                   locals: { faq: @faq, frame_id: "faq_attachment_#{@faq.id}",
                                             shop_origin: @shop_origin, host: @host })
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("faq_attachment_#{@faq.id}") {
          "<turbo-frame id=\"faq_attachment_#{@faq.id}\">#{upload_html}</turbo-frame>".html_safe
        }
      end
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  private

  def set_shop_context
    @shop_origin = current_shopify_domain
    @host        = params[:host]
  end

  def set_faq
    @faq = current_shop.training_documents.find(params[:id])
  end

  def set_faq_for_attachment
    @faq_for_attachment = current_shop.training_documents
                                      .where(document_type: "faq")
                                      .find(params[:faq_id])
  end

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end

  def ordered_faqs
    current_shop.training_documents.where(document_type: "faq").order(:created_at)
  end

  def faq_params
    params.require(:training_document).permit(:title, :content)
  end

  def attachment_params
    params.require(:attachment).permit(:file)
  end

  def parse_faq_params
    raw = params.permit(faqs: {})[:faqs] || {}
    raw.values.select { |f| f["selected"] == "1" }
  end

  def save_faq_items(faq_items, context)
    imported = faq_items.filter_map do |item|
      question = item["question"].to_s.strip
      answer   = item["answer"].to_s.strip
      next if question.blank? || answer.blank?

      current_shop.training_documents.create!(
        document_type: "faq",
        title:         question,
        content:       answer
      )
    end

    if imported.empty?
      error_id = context == "suggest_import" ? "faq_suggestion_import_error" : "faq_import_result_error"
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: ts_replace(error_id, "knowledge_base/shared/error_banner",
                                          id: error_id, title: "Import failed",
                                          messages: [ "All selected FAQs had blank questions or answers. Nothing was saved." ])
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
      return nil
    end

    imported
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[FaqsController##{context}] Save failed: #{e.message}")
    error_id = context == "suggest_import" ? "faq_suggestion_import_error" : "faq_import_result_error"
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: ts_replace(error_id, "knowledge_base/shared/error_banner",
                                        id: error_id, title: "Import failed",
                                        messages: [ "Failed to save FAQs: #{e.record.errors.full_messages.to_sentence}" ])
      end
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
    nil
  end

  # ── Turbo stream helpers ──────────────────────────────────────────────────────

  # Safe replace: uses render_to_string so it doesn't trigger double-render.
  # formats: [:html] prevents Rails from looking for .turbo_stream.erb partials.
  def ts_replace(dom_id, partial, locals = {})
    html = render_to_string(partial: partial, locals: locals, formats: [ :html ])
    turbo_stream.replace(dom_id) { html.html_safe }
  end

  # Safe append variant.
  def ts_append(dom_id, partial, locals = {})
    html = render_to_string(partial: partial, locals: locals, formats: [ :html ])
    turbo_stream.append(dom_id) { html.html_safe }
  end

  # Appends a <script> tag to body so JS fires after Turbo applies the streams.
  def ts_js(js)
    turbo_stream.append("body") { "<script>#{js}</script>".html_safe }
  end

  def empty_div(id, **attrs)
    attr_str = attrs.map { |k, v| " #{k}=\"#{v}\"" }.join
    "<div id=\"#{id}\"#{attr_str}></div>".html_safe
  end

  def import_success_streams(panel_target, panel_partial, modal_id, banner_id, banner_title)
    total_faqs = current_shop.training_documents.where(document_type: "faq").count
    panel_html = render_to_string(partial: panel_partial, formats: [ :html ], locals: { shop_origin: @shop_origin, host: @host })

    streams = [
      turbo_stream.replace(panel_target) {
        "<turbo-frame id=\"#{panel_target}\">#{panel_html}</turbo-frame>".html_safe
      },
      turbo_stream.replace("faq_empty_state") { empty_div("faq_empty_state") },
      ts_replace("faq_count_badge", "knowledge_base/shared/count_badge",
                 id: "faq_count_badge", count: total_faqs, label: "FAQ"),
      turbo_stream.prepend("faq_list") {
        "<div id=\"#{banner_id}\" style=\"margin-bottom:6px;\"><s-banner tone=\"success\" title=\"#{banner_title}\" onDismiss=\"this.remove()\"></s-banner></div>".html_safe
      }
    ]

    @imported_faqs.each do |faq|
      streams << ts_append("faq_list", "knowledge_base/faqs/faq",
                           faq: faq, shop_origin: @shop_origin, host: @host)
    end

    streams << ts_js(<<~JS)
      (function() {
        var modal = document.getElementById('#{modal_id}');
        if (modal && typeof modal.hideOverlay === 'function') { modal.hideOverlay(); }
      })();
    JS

    streams
  end
end
