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

      if shop
        @conversations_count  = shop.conversations.count
        @tickets_count        = shop.tickets.count
        @open_tickets_count   = shop.tickets.where(status: "open").count
        @customers_count      = shop.customers.count
        @recent_conversations = shop.conversations.includes(:customer, :messages)
                                    .order(last_message_at: :desc, created_at: :desc)
                                    .limit(5)
        @current_plan         = shop.plan
      else
        @conversations_count  = 0
        @tickets_count        = 0
        @open_tickets_count   = 0
        @customers_count      = 0
        @recent_conversations = []
        @current_plan         = nil
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

    session = ShopifyAPI::Auth::Session.new(
      shop: current_shopify_domain,
      access_token: Shop.find_by(shopify_domain: current_shopify_domain)&.shopify_token
    )
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
