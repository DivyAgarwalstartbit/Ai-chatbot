module Shopify
  class ProductImportService
    def initialize(shop)
      @shop = shop
    end

    def call(product_data)
      product = import_product(product_data)

      product_data.dig("variants", "edges")&.each do |edge|
        import_variant(edge["node"], product)
      end

      ProductEmbeddingJob.perform_later(product.id)

      product
    end

    def import_product(data)
      Product.find_or_initialize_by(
        shop_id: @shop.id,
        shopify_product_id: shopify_id(data["id"])
      ).tap do |product|
        product.title        = data["title"]
        product.description  = data["description"]
        ai_val = data.dig("metafield", "value")
        product.ai_info = ai_val if ai_val.present?
        product.handle       = data["handle"]
        product.image_url    = data.dig("featuredMedia", "image", "url")
        product.product_type = data["productType"] if data["productType"].present?
        product.tags         = data["tags"]         if data["tags"].present?

        collections = data.dig("collections", "edges")
        if collections.present?
          product.collections_data = collections.map { |e|
            { "id" => shopify_id(e.dig("node", "id")), "title" => e.dig("node", "title"), "handle" => e.dig("node", "handle") }
          }
        end

        product.save!
      end
    end

    def import_variant(data, product)
      return unless product

      ProductVariant.find_or_initialize_by(
        shop_id:           @shop.id,
        shopify_variant_id: shopify_id(data["id"])
      ).tap do |variant|
        variant.product             = product
        variant.title               = data["title"]
        variant.sku                 = data["sku"]
        variant.price               = data["price"]
        variant.compare_at_price    = data["compareAtPrice"]
        variant.inventory_quantity  = data["inventoryQuantity"]
        variant.available           = data["inventoryQuantity"].to_i > 0
        variant.options             = data["selectedOptions"]
        variant.save!
      end
    end

    def shopify_id(gid)
      gid.split("/").last
    end
  end
end
