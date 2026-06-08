# frozen_string_literal: true

# Handles Shopify policy sync for shipping and return policies.
#
# Routes:
#   POST /knowledge_base/shipping_policy/sync   → sync :shipping_policy
#   POST /knowledge_base/return_policy/sync     → sync :return_policy
#
# Both actions share a single #sync action parameterised by :policy_type
# (injected via the route defaults).
#
# Flow:
#   1. Fetch policy content from Shopify GraphQL
#   2. If merchant already has shopify_content → respond with confirmation
#      prompt (Turbo Stream shows inline confirm banner)
#   3. On confirmed=true → upsert shopify_content + synced_at, set source_type
#   4. Respond with Turbo Stream refreshing summary + preview + actions
#
class KnowledgeBase::PolicySyncsController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: %i[sync]
  before_action :set_shop_context

  # POST /knowledge_base/shipping_policy/sync
  # POST /knowledge_base/return_policy/sync
  def sync
    policy_type = params[:policy_type]
    confirmed   = params[:confirmed] == "true"

    unless %w[shipping_policy return_policy].include?(policy_type)
      return render_sync_error("Unknown policy type.", policy_type)
    end

    # Fetch from Shopify
    fetch_result = Shopify::PolicyFetchService.new(shopify_session).call(policy_type)

    unless fetch_result.success?
      return render_sync_error(fetch_result.error, policy_type)
    end

    policy = current_shop.training_documents
                         .with_attached_file
                         .find_or_initialize_by(document_type: policy_type)

    # If there's existing Shopify content and merchant hasn't confirmed replacement,
    # return a confirmation prompt instead of overwriting.
    if policy.shopify_content.present? && !confirmed
      @policy_type    = policy_type
      @new_content    = fetch_result.content
      @shop_origin    = @shop_origin
      @host           = @host
      return respond_to do |format|
        format.turbo_stream { render :confirm }
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
      end
    end

    # Persist: write shopify_content separately, preserve manual content untouched.
    policy.title          ||= policy_type.humanize
    policy.shopify_content  = fetch_result.content
    policy.synced_at        = Time.current

    # Add shopify_sync to source_type list (may already contain manual_entry)
    policy.source_type = add_source(policy.source_type, "shopify_sync")

    policy.save!

    @policy      = policy
    @policy_type = policy_type

    respond_to do |format|
      format.turbo_stream { render :sync }
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  rescue ActiveRecord::RecordInvalid => e
    render_sync_error("Failed to save policy: #{e.record.errors.full_messages.to_sentence}", params[:policy_type])
  rescue => e
    Rails.logger.error("[PolicySyncsController] Unexpected: #{e.class} #{e.message}")
    render_sync_error("An unexpected error occurred. Please try again.", params[:policy_type])
  end

  private

  def set_shop_context
    @shop_origin = current_shopify_domain
    @host        = params[:host]
  end

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end

  # Builds a ShopifyAPI session from the authenticated shop record.
  def shopify_session
    ShopifyAPI::Auth::Session.new(
      shop:         current_shop.shopify_domain,
      access_token: current_shop.shopify_token
    )
  end

  # source_type is a space-separated list of source tokens, e.g. "manual_entry shopify_sync"
  def add_source(current, new_source)
    sources = current.to_s.split
    sources << new_source unless sources.include?(new_source)
    sources.join(" ")
  end

  def render_sync_error(message, policy_type)
    @error       = message
    @policy_type = policy_type
    respond_to do |format|
      format.turbo_stream { render :sync_error }
      format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1) }
    end
  end
end
