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
    end
  end
end
