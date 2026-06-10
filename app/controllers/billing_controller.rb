# frozen_string_literal: true

class BillingController < ApplicationController
  include ShopifyApp::EmbeddedApp
  include ShopifyApp::ShopAccessScopesVerification

  SUBSCRIPTION_MUTATION = <<~GRAPHQL.freeze
    mutation AppSubscriptionCreate($name: String!, $lineItems: [AppSubscriptionLineItemInput!]!, $returnUrl: URL!, $test: Boolean!, $trialDays: Int) {
      appSubscriptionCreate(name: $name, returnUrl: $returnUrl, lineItems: $lineItems, test: $test, trialDays: $trialDays) {
        userErrors { field message }
        appSubscription { id }
        confirmationUrl
      }
    }
  GRAPHQL

  SHOP_PLAN_QUERY = <<~GRAPHQL.freeze
    query { shop { plan { partnerDevelopment } } }
  GRAPHQL

  AUTH_ERROR_PATTERN = /RefreshTokenExpired|Non-expiring access tokens|Invalid API key/.freeze

  def create
    session = shop_session
    client  = graphql_client(session)

    plan      = client.query(query: SHOP_PLAN_QUERY).body.dig("data", "shop", "plan") || {}
    test_mode = plan["partnerDevelopment"] == true && ENV["allowFreeDevelopment"] == "true"

    vars             = subscription_variables(test_mode)
    Rails.logger.info("[Billing#create] variables: #{vars.to_json}")

    response         = client.query(query: SUBSCRIPTION_MUTATION, variables: vars)
    Rails.logger.info("[Billing#create] response body: #{response.body.to_json}")

    errors           = response.body.dig("data", "appSubscriptionCreate", "userErrors")
    confirmation_url = response.body.dig("data", "appSubscriptionCreate", "confirmationUrl")

    Rails.logger.error("[Billing#create] userErrors: #{errors}") if errors&.any?
    raise "Failed to get confirmation URL: #{errors&.map { |e| e['message'] }.join(', ')}" if confirmation_url.blank?

    render(
      "shopify_app/shared/redirect",
      layout: false,
      locals: {
        url: confirmation_url,
        current_shopify_domain: current_shopify_domain
      }
    )
  rescue => e
    Rails.logger.error "[Billing#create] #{e.message}"
    return redirect_to("/login?shop=#{current_shopify_domain}") if e.message.to_s.match?(AUTH_ERROR_PATTERN)

    render plain: "Billing setup failed: #{e.message}", status: :unprocessable_entity
  end

  def callback
    shop = Shop.find_by(shopify_domain: current_shopify_domain)
    return redirect_to(root_path, alert: "Shop not found") if shop.nil?

    if params[:charge_id].present?
      plan_key = Shop::PLANS.key?(params[:plan]) ? params[:plan] : "starter"
      shop.update!(charge_id: params[:charge_id].to_s, paid: true, plan: plan_key)
      if params[:host].present?
        redirect_to ShopifyAPI::Auth.embedded_app_url(params[:host]) + "/?shop=#{current_shopify_domain}&host=#{params[:host]}&embedded=1",
                    allow_other_host: true
      else
        redirect_to root_path(shop: current_shopify_domain, embedded: 1)
      end
    else
      redirect_to plans_path(shop: current_shopify_domain, host: params[:host], embedded: 1)
    end
  rescue => e
    Rails.logger.error "[Billing#callback] #{e.message}"
    redirect_to root_path(shop: current_shopify_domain, host: params[:host], embedded: 1)
  end

  private

  def shop_session
    shop = Shop.find_by!(shopify_domain: current_shopify_domain)
    shop.refresh_token_if_expired! if shop.respond_to?(:refresh_token_if_expired!)
    session = Shop.retrieve_by_shopify_domain(current_shopify_domain)
    ShopifyAPI::Context.activate_session(session)
    session
  end

  def graphql_client(session)
    ShopifyAPI::Clients::Graphql::Admin.new(session: session)
  end

  def subscription_variables(test_mode)
    plan_key = Shop::PLANS.key?(params[:plan]) ? params[:plan] : "starter"
    plan_def = Shop::PLANS[plan_key]

    query_string = { shop: current_shopify_domain, host: params[:host], embedded: 0, plan: plan_key }.to_query
    {
      name:      plan_def[:name],
      returnUrl: "#{ENV['HOST'] || ENV['current_host']}/billing/callback?#{query_string}",
      test:      test_mode,
      trialDays: plan_def[:trial_days],
      lineItems: [ {
        plan: {
          appRecurringPricingDetails: {
            price:    { amount: plan_def[:price], currencyCode: "USD" },
            interval: "EVERY_30_DAYS"
          }
        }
      } ]
    }
  end
end
