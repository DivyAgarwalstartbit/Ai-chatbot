# frozen_string_literal: true

class ProductSyncMailer < ApplicationMailer
  def sync_completed(shop:, product_count:)
    @shop          = shop
    @product_count = product_count
    @synced_at     = shop.products_synced_at || Time.current

    mail(
      to:      merchant_email,
      subject: "✅ Product sync completed — #{@product_count} #{"product".pluralize(@product_count)} synced"
    )
  end

  private

  def merchant_email
    vr = (@shop.ai_shopper_configuration&.visibility_rules || {}).with_indifferent_access
    vr[:support_email].presence || ENV.fetch("SMTP_USERNAME", nil)
  end
end