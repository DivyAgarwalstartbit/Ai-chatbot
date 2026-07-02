# frozen_string_literal: true

class HomeController < ApplicationController
  include ShopifyApp::EmbeddedApp
  include ShopifyApp::EnsureInstalled
  include ShopifyApp::ShopAccessScopesVerification

  def index
    if ShopifyAPI::Context.embedded? && (!params[:embedded].present? || params[:embedded] != "1")
      redirect_url = ShopifyAPI::Auth.embedded_app_url(params[:host]) + request.path
      redirect_url = ShopifyApp.configuration.root_url if deduced_phishing_attack?(redirect_url)
      redirect_to(redirect_url, allow_other_host: true)
    else
      @shop_origin = current_shopify_domain
      @host        = params[:host]
      shop         = Shop.find_by(shopify_domain: @shop_origin)

      # Redirect to plans page on first install (no plan selected yet)
      if shop && shop.plan.nil? && params[:skip_plan_redirect].blank?
        return redirect_to plans_path(shop: @shop_origin, host: @host, embedded: 1)
      end

      if shop
        @conversations_count  = shop.conversations.count
        @tickets_count        = shop.tickets.count
        @open_tickets_count   = shop.tickets.where(status: "open").count
        @customers_count      = shop.customers.count
        @recent_conversations = shop.conversations.includes(:customer, :messages)
                                    .order(last_message_at: :desc, created_at: :desc)
                                    .limit(5)
        @current_plan         = shop.plan
        @shop_usage_sub_id    = shop.usage_subscription_id

        # Plan limits for usage display (uses effective limits which include overage bundles)
        @plan_label = shop.plan_label
        faq_count = shop.training_documents.where(document_type: "faq").count
        doc_count = shop.training_documents.where(document_type: "uploaded_document").count
        @usage = {
          conversations: { used: @conversations_count, limit: shop.effective_conversation_limit, label: "Conversations" },
          tickets:       { used: @tickets_count,        limit: shop.effective_ticket_limit,       label: "Support tickets" },
          faqs:          { used: faq_count,             limit: shop.effective_faq_limit,          label: "FAQs" },
          documents:     { used: doc_count,             limit: shop.effective_document_limit,     label: "Documents" }
        }

        if shop.pro?
          @monthly_bundles      = shop.overage_bundles.this_month.order(charged_at: :desc)
          @monthly_overage_cost = @monthly_bundles.sum(:amount)
        end

      else
        @conversations_count      = 0
        @tickets_count            = 0
        @open_tickets_count       = 0
        @customers_count          = 0
        @recent_conversations     = []
        @current_plan             = nil
        @bot_configured           = false
        @bot_name                 = "AI Shopper"
        @knowledge_base_populated = false
        @knowledge_base_count     = 0
      end

      @app_embed_enabled = check_app_embed_enabled
    end
  end

  def check_app_embed_status
    @shop_origin = current_shopify_domain
    enabled = check_app_embed_enabled
    if enabled
      render json: { success: true }
    else
      render json: { success: false, msg: "App embed is not enabled. Please enable it in your theme settings." }
    end
  end

  private

  def check_app_embed_enabled
    return true if ENV["APP_EMBED_ID"].blank?

    shop = Shop.find_by(shopify_domain: current_shopify_domain)
    return true unless shop
    shop.refresh_token_if_expired! if shop.respond_to?(:refresh_token_if_expired!)
    session = Shop.retrieve_by_shopify_domain(current_shopify_domain)
    return true unless session
    ShopifyAPI::Context.activate_session(session)
    client = ShopifyAPI::Clients::Rest::Admin.new(session: session)

    # Find the published theme
    themes_response = client.get(path: "themes.json")
    themes = themes_response.body.dig("themes") || []
    published_theme = themes.find { |t| t["role"] == "main" }
    return true unless published_theme

    theme_id = published_theme["id"]

    # Fetch the theme's settings_data asset
    asset_response = client.get(
      path: "themes/#{theme_id}/assets.json",
      query: { "asset[key]" => "config/settings_data.json" }
    )
    asset_value = asset_response.body.dig("asset", "value")
    return true unless asset_value

    json_data = JSON.parse(asset_value)
    blocks    = json_data.dig("current", "blocks")

    !!(blocks&.any? do |_, block|
      block["type"].to_s.include?(ENV["APP_EMBED_ID"].to_s) && block["disabled"] == false
    end)
  rescue => e
    Rails.logger.error "[HomeController] App embed check failed: #{e.message}"
    true # default to hidden banner on API error
  end
end
