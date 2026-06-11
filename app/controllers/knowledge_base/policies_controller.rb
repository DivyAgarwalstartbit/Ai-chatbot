# frozen_string_literal: true

# Handles show, update, sync, and attachment CRUD for both policy types.
# :policy_type is injected via route defaults (:shipping_policy or :return_policy).
class KnowledgeBase::PoliciesController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: %i[update sync create_attachment destroy_attachment]

  before_action :set_shop_context
  before_action :set_policy_type
  before_action :set_policy, only: %i[show update sync]
  before_action :set_policy_for_attachment, only: %i[new_attachment create_attachment destroy_attachment]

  def show
  end

  def update
    @policy.assign_attributes(policy_params)
    @policy.title       ||= @policy_type.humanize
    @policy.source_type   = add_source(@policy.source_type, "manual_entry")

    if @policy.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            ts_replace("#{@policy_type}_preview_area", "knowledge_base/bases/policy_preview",
                       policy: @policy, policy_type: @policy_type,
                       empty_message: helpers.policy_empty_message(@policy_type)),
            ts_replace("#{@policy_type}_badge", "knowledge_base/bases/policy_badge",
                       policy: @policy, policy_type: @policy_type),
            ts_replace("#{@policy_type}_summary", "knowledge_base/bases/policy_summary",
                       policy: @policy, policy_type: @policy_type),
            ts_js(<<~JS)
              (function() {
                var overlay = document.getElementById('#{@policy_type}_modal');
                if (overlay) { overlay.style.display = 'none'; document.body.style.overflow = ''; }
              })();
            JS
          ]
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1), notice: "#{@policy_type.humanize} saved." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: [] }
        format.html { render :show, status: :unprocessable_entity }
      end
    end
  end

  def sync
    confirmed = params[:confirmed] == "true"

    fetch_result = Shopify::PolicyFetchService.new(shopify_session).call(@policy_type)
    return render_sync_error(fetch_result.error) unless fetch_result.success?

    if @policy.shopify_content.present? && !confirmed
      confirm_url = @policy_type == "shipping_policy" ?
        sync_knowledge_base_shipping_policy_path(shop: @shop_origin, host: @host, embedded: 1) :
        sync_knowledge_base_return_policy_path(shop: @shop_origin, host: @host, embedded: 1)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            ts_replace("#{@policy_type}_sync_banner", "knowledge_base/policies/sync_confirm_banner",
                       policy_type: @policy_type, confirm_url: confirm_url,
                       shop_origin: @shop_origin, host: @host),
            ts_js(<<~JS)
              (function() {
                var btn = document.getElementById('#{@policy_type}_sync_btn');
                if (btn) { btn.removeAttribute('loading'); btn.removeAttribute('disabled'); }
              })();
            JS
          ]
        end
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
      return
    end

    @policy.title         ||= @policy_type.humanize
    @policy.shopify_content = fetch_result.content
    @policy.synced_at       = Time.current
    @policy.source_type     = add_source(@policy.source_type, "shopify_sync")
    @policy.save!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("#{@policy_type}_sync_banner") { "<div id=\"#{@policy_type}_sync_banner\"></div>".html_safe },
          ts_replace("#{@policy_type}_summary", "knowledge_base/bases/policy_summary",
                     policy: @policy, policy_type: @policy_type),
          ts_replace("#{@policy_type}_preview_area", "knowledge_base/bases/policy_preview",
                     policy: @policy, policy_type: @policy_type, empty_message: ""),
          ts_replace("#{@policy_type}_badge", "knowledge_base/bases/policy_badge",
                     policy: @policy, policy_type: @policy_type),
          ts_js(<<~JS)
            (function() {
              var btn = document.getElementById('#{@policy_type}_sync_btn');
              if (btn) { btn.removeAttribute('loading'); btn.removeAttribute('disabled'); }
            })();
          JS
        ]
      end
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  rescue ActiveRecord::RecordInvalid => e
    render_sync_error("Failed to save policy: #{e.record.errors.full_messages.to_sentence}")
  rescue => e
    Rails.logger.error("[PoliciesController] Unexpected: #{e.class} #{e.message}")
    render_sync_error("An unexpected error occurred. Please try again.")
  end

  def new_attachment
  end

  def create_attachment
    if attachment_params[:file].blank?
      return render_attachment_error("Please select a file to upload.")
    end

    @policy.file.attach(attachment_params[:file])
    @policy.assign_attributes(
      processing_status: "pending",
      processing_error:  nil,
      embedding_status:  "pending",
      embedding_error:   nil,
      source_type:       add_source(@policy.source_type, "uploaded_document")
    )

    if @policy.save
      ProcessDocumentJob.perform_later(@policy.id)

      respond_to do |format|
        format.turbo_stream { render turbo_stream: policy_attachment_refresh_streams }
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    else
      render_attachment_error(@policy.errors.full_messages.to_sentence)
    end
  end

  def destroy_attachment
    @policy.file.purge
    @policy.reload
    # Clear the extracted text — it came from the file, not manual entry.
    # Also remove uploaded_document from source_type.
    was_only_document = !@policy.source_type.to_s.include?("manual_entry")
    @policy.source_type = remove_source(@policy.source_type, "uploaded_document")
    @policy.content     = nil if was_only_document
    @policy.save(validate: false)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: policy_attachment_refresh_streams + [
          ts_js(<<~JS)
            (function() {
              var fileInput = document.getElementById('#{@policy_type}_file_input');
              if (fileInput) fileInput.value = '';
            })();
          JS
        ]
      end
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  private

  def set_shop_context
    @shop_origin = current_shopify_domain
    @host        = params[:host]
  end

  def set_policy_type
    @policy_type = params[:policy_type]
    unless %w[shipping_policy return_policy].include?(@policy_type)
      render plain: "Unknown policy type", status: :bad_request
    end
  end

  def set_policy
    @policy = current_shop.training_documents
                          .with_attached_file
                          .find_or_initialize_by(document_type: @policy_type)
  end

  def set_policy_for_attachment
    @policy = current_shop.training_documents
                          .find_or_initialize_by(document_type: @policy_type)
    @policy.title ||= @policy_type.humanize
    @policy.save! if @policy.new_record?
  end

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end

  def shopify_session
    ShopifyAPI::Auth::Session.new(
      shop:         current_shop.shopify_domain,
      access_token: current_shop.shopify_token
    )
  end

  def add_source(current, new_source)
    sources = current.to_s.split
    sources << new_source unless sources.include?(new_source)
    sources.join(" ")
  end

  def remove_source(current, source)
    current.to_s.split.reject { |s| s == source }.join(" ")
  end

  def policy_params
    params.require(:training_document).permit(:content)
  end

  def attachment_params
    params.require(:attachment).permit(:file)
  end

  # Builds a turbo_stream.replace using render_to_string (safe in controller context).
  # formats: [:html] prevents Rails from looking for .turbo_stream.erb partials.
  def ts_replace(dom_id, partial, locals = {})
    html = render_to_string(partial: partial, locals: locals, formats: [ :html ])
    turbo_stream.replace(dom_id) { html.html_safe }
  end

  # Appends an inline <script> tag to body so it fires after Turbo applies streams.
  def ts_js(js)
    turbo_stream.append("body") { "<script>#{js}</script>".html_safe }
  end

  def render_sync_error(message)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          ts_replace("#{@policy_type}_sync_banner", "knowledge_base/policies/sync_error_banner",
                     policy_type: @policy_type, error: message),
          ts_js(<<~JS)
            (function() {
              var btn = document.getElementById('#{@policy_type}_sync_btn');
              if (btn) { btn.removeAttribute('loading'); btn.removeAttribute('disabled'); }
            })();
          JS
        ]
      end
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end

  def render_attachment_error(message)
    respond_to do |format|
      format.turbo_stream do
        error_html = render_to_string(partial: "knowledge_base/shared/error_banner",
                                      locals: { id: nil, title: nil, messages: [ message ] })
        render turbo_stream: turbo_stream.replace("#{@policy_type}_attachment_section") {
          "<turbo-frame id=\"#{@policy_type}_attachment_section\">#{error_html}</turbo-frame>".html_safe
        }
      end
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1), alert: message }
    end
  end

  def policy_attachment_refresh_streams
    [
      ts_replace("#{@policy_type}_attachment_area", "knowledge_base/bases/policy_attachment",
                 policy: @policy, policy_type: @policy_type, shop_origin: @shop_origin, host: @host),
      ts_replace("#{@policy_type}_preview_area", "knowledge_base/bases/policy_preview",
                 policy: @policy, policy_type: @policy_type,
                 empty_message: helpers.policy_empty_message(@policy_type)),
      ts_replace("#{@policy_type}_badge", "knowledge_base/bases/policy_badge",
                 policy: @policy, policy_type: @policy_type),
      ts_replace("#{@policy_type}_summary", "knowledge_base/bases/policy_summary",
                 policy: @policy, policy_type: @policy_type),
      ts_replace("#{@policy_type}_actions", "knowledge_base/bases/policy_actions",
                 policy: @policy, policy_type: @policy_type, shop_origin: @shop_origin, host: @host)
    ]
  end
end
