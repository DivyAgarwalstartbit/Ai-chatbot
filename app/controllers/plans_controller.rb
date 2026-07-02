# frozen_string_literal: true

class PlansController < ApplicationController
  include ShopifyApp::EmbeddedApp
  include ShopifyApp::EnsureInstalled

  def index
    if ShopifyAPI::Context.embedded?
      return redirect_to("/login?shop=#{params[:shop].presence || current_shopify_domain}") if params[:host].blank?

      if params[:embedded] != "1"
        return redirect_to(ShopifyAPI::Auth.embedded_app_url(params[:host]) + request.path, allow_other_host: true)
      end
    end

    @shop_origin  = current_shopify_domain
    @host         = params[:host]
    @shop         = Shop.find_by(shopify_domain: @shop_origin)
    @current_plan = @shop&.plan
    @is_dev_store = dev_store?
  end

  private

  def dev_store?
    session = Shop.retrieve_by_shopify_domain(current_shopify_domain)
    return false if session.blank?
    ShopifyAPI::Context.activate_session(session)
    client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)
    result = client.query(query: "query { shop { plan { partnerDevelopment } } }")
    result.body.dig("data", "shop", "plan", "partnerDevelopment") == true
  rescue => e
    Rails.logger.warn("[PlansController] dev_store? check failed: #{e.message}")
    false
  end
end
