# frozen_string_literal: true

# Fetches shop policy content from the Shopify Admin GraphQL API.
#
# Shopify exposes all policies through shop.shopPolicies, which returns an
# array of policy nodes each with a `type` enum, `title`, and `body` (HTML).
#
# Usage:
#   session = ShopifyAPI::Auth::Session.new(shop: shop.shopify_domain,
#                                           access_token: shop.shopify_token)
#   result = Shopify::PolicyFetchService.new(session).call("shipping_policy")
#   result.success?  # => true
#   result.content   # => "We ship within 2 business days..."
#   result.error     # => nil
#
class Shopify::PolicyFetchService
  Result = Struct.new(:content, :error, keyword_init: true) do
    def success? = error.nil?
  end

  # Maps Shopify's GraphQL enum values to our internal document_type strings.
  POLICY_ENUM_MAP = {
    "SHIPPING_POLICY"  => "shipping_policy",
    "REFUND_POLICY"    => "return_policy",
    "PRIVACY_POLICY"   => "privacy_policy",
    "TERMS_OF_SERVICE" => "terms_of_service"
  }.freeze

  # Inverse map — our document_type → Shopify enum, used to look up the right
  # policy from the returned array.
  SUPPORTED_TYPES = POLICY_ENUM_MAP.invert.freeze

  QUERY = <<~GRAPHQL
    query FetchPolicies {
      shop {
        shopPolicies {
          type
          title
          body
        }
      }
    }
  GRAPHQL

  def initialize(session)
    @session = session
  end

  # @param policy_type [String] e.g. "shipping_policy" or "return_policy"
  # @return [Result]
  def call(policy_type)
    unless SUPPORTED_TYPES.key?(policy_type.to_s)
      return Result.new(content: nil, error: "Unknown policy type: #{policy_type}")
    end

    client   = ShopifyAPI::Clients::Graphql::Admin.new(session: @session)
    response = client.query(query: QUERY)
    body     = response.body

    # GraphQL errors come back as body["errors"], not as an HTTP error code.
    if body["errors"].present?
      messages = body["errors"].map { |e| e["message"] }.join(", ")
      Rails.logger.error("[PolicyFetchService] GraphQL errors for #{policy_type}: #{messages}")
      return Result.new(content: nil, error: "Shopify API error: #{messages}")
    end

    policies_array = body.dig("data", "shop", "shopPolicies") || []

    # Build a lookup hash keyed by our internal document_type strings.
    parsed = {}
    policies_array.each do |policy|
      mapped_key = POLICY_ENUM_MAP[policy["type"]]
      parsed[mapped_key] = { "title" => policy["title"], "body" => policy["body"] } if mapped_key
    end

    policy_data = parsed[policy_type.to_s]

    if policy_data.nil?
      return Result.new(
        content: nil,
        error:   "Could not find #{policy_type.to_s.humanize} in your Shopify store. " \
                 "Make sure it's configured under Shopify Admin → Settings → Policies."
      )
    end

    html = policy_data["body"].to_s.strip

    if html.blank?
      return Result.new(
        content: nil,
        error:   "Your Shopify #{policy_type.to_s.humanize.downcase} is empty. " \
                 "Add content in Shopify Admin → Settings → Policies, then sync again."
      )
    end

    Result.new(content: strip_html(html), error: nil)

  rescue ShopifyAPI::Errors::HttpResponseError => e
    Rails.logger.error("[PolicyFetchService] HTTP #{e.code} for #{policy_type}: #{e.message}")
    Result.new(content: nil, error: shopify_http_error_message(e.code))
  rescue => e
    Rails.logger.error("[PolicyFetchService] Unexpected error: #{e.class} #{e.message}")
    Result.new(content: nil, error: "Could not connect to Shopify. Please try again.")
  end

  private

  def strip_html(html)
    html
      .gsub(/<br\s*\/?>/, "\n")
      .gsub(%r{</(p|div|h[1-6]|li|tr)>}i, "\n")
      .gsub(/<li[^>]*>/i, "• ")
      .gsub(/<[^>]+>/, "")
      .gsub(/&amp;/, "&")
      .gsub(/&lt;/, "<")
      .gsub(/&gt;/, ">")
      .gsub(/&nbsp;/, " ")
      .gsub(/&quot;/, '"')
      .gsub(/&#39;/, "'")
      .gsub(/\n{3,}/, "\n\n")
      .strip
  end

  def shopify_http_error_message(code)
    case code
    when 401 then "Authentication failed. Please reinstall the app."
    when 403 then "The app does not have permission to read store policies."
    when 429 then "Shopify rate limit reached. Please wait a moment and try again."
    else          "Shopify returned an error (#{code}). Please try again."
    end
  end
end
