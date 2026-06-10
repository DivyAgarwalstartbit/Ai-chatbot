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
  end
end
