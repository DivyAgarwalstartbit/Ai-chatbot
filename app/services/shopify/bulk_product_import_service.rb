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

      product_map = {}

      URI.open(@url) do |file|
        file.each_line do |line|
          data = JSON.parse(line)

          if product?(data)
            importer = Shopify::ProductImportService.new(@shop)

            product = importer.import_product(data)
            product_map[data["id"]] = product.id

          elsif variant?(data)
            importer = Shopify::ProductImportService.new(@shop)
            shopify_parent_gid = data["__parentId"]

local_product_id = product_map[shopify_parent_gid]

unless local_product_id
  Rails.logger.warn(
    "Missing parent product for variant #{data['id']}, parent=#{shopify_parent_gid}"
  )
  next
end

importer.import_variant(data, local_product_id)
          end
        end
      end

      Rails.logger.info "BulkProductImportService: saved #{product_map.size} products, queuing embeddings"

      product_map.values.each do |product_id|
        ProductEmbeddingJob.perform_later(product_id)
      end
    end

    private

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
