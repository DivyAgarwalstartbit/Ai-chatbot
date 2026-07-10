require "open-uri"
require "json"

module Shopify
  class BulkProductImportService
    def initialize(shop, url)
      @shop = shop
      @url  = url
    end

    def call
      Rails.logger.info "BulkProductImportService: clearing existing products..."
      delete_local_products

      Rails.logger.info "BulkProductImportService: downloading #{@url}"

      product_limit    = @shop.effective_product_limit
      product_map      = {}
      limit_email_sent = false

      URI.open(@url) do |file|
        file.each_line do |line|
          data = JSON.parse(line)

          if product?(data)
            # Free / Starter: hard-cap at plan limit
            unless @shop.pro?
              if product_map.size >= product_limit
                Rails.logger.info "BulkProductImportService: product limit (#{product_limit}) reached for #{@shop.plan_label} plan — skipping remaining products"
                unless limit_email_sent
                  notify_limit_email
                  limit_email_sent = true
                end
                next
              end
            end

            importer = Shopify::ProductImportService.new(@shop)
            product  = importer.import_product(data)
            product_map[data["id"]] = product.id

          elsif variant?(data)
            importer           = Shopify::ProductImportService.new(@shop)
            shopify_parent_gid = data["__parentId"]
            local_product_id   = product_map[shopify_parent_gid]

            unless local_product_id
              Rails.logger.warn "Missing parent product for variant #{data['id']}, parent=#{shopify_parent_gid}"
              next
            end

            product = Product.find(local_product_id)
            importer.import_variant(data, product)
          end
        end
      end

      Rails.logger.info "BulkProductImportService: saved #{product_map.size}/#{product_limit} products, queuing embeddings"

      # Pro: charge overage bundles for every 10 products imported beyond the plan limit
      if @shop.overage_eligible?
        overage_count = product_map.size - product_limit
        if overage_count > 0
          bundles_needed = (overage_count.to_f / Shop::OVERAGE_BUNDLE[:products]).ceil
          Rails.logger.info "BulkProductImportService: charging #{bundles_needed} overage bundle(s) for #{overage_count} extra products"
          bundles_needed.times do
            OverageService.new(shop: @shop, resource_type: :product).check_and_charge!
          end
        end
      end

      # Sync collection membership — Shopify bulk API only allows one nested
      # connection (used by variants), so we do this in a separate GraphQL call.
      Shopify::CollectionSyncService.new(@shop).call

      product_map.values.each do |product_id|
        ProductEmbeddingJob.perform_later(product_id)
      end
    end

    private

    def notify_limit_email
      return unless @shop.starter?
      cache_key = "limit_email:#{@shop.id}:product:#{Date.current}"
      return if Rails.cache.exist?(cache_key)
      Rails.cache.write(cache_key, true, expires_in: 1.day)
      LimitReachedMailer.limit_reached(shop: @shop, resource: :product).deliver_later
    end

    def delete_local_products
      @shop.products.destroy_all
    end

    def product?(data)
      data["id"].include?("Product/")
    end

    def variant?(data)
      data["id"].include?("ProductVariant/")
    end
  end
end
