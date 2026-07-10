module Ai
  class ProductQueryAnalyzerService
    def initialize(message:, previous_data: {}, uses_previous_context: false, shop: nil)
      @message               = message.to_s.strip
      @previous_data         = previous_data || {}
      @uses_previous_context = uses_previous_context
      @shop                  = shop
    end

    # ==================================================
    # ENTRY
    # ==================================================
    def call
      raw      = llm_call
      new_data = parse_response(raw)

      result = @uses_previous_context ? merge_with_previous(new_data) : normalize_fresh(new_data)
      Rails.logger.info("ProductQueryAnalyzer => #{result.inspect}")
      result
    rescue => e
      Rails.logger.error("ProductQueryAnalyzerService Error: #{e.message}")
      fallback_response
    end

    private

    # ==================================================
    # LLM CALL
    # ==================================================
    def llm_call
      Ai::GroqService.new([
        { role: "system", content: system_prompt },
        { role: "user",   content: @message }
      ], name: "product_query_analyzer").call
    end

    # ==================================================
    # SYSTEM PROMPT
    # ==================================================
    def system_prompt
      store_ctx = Ai::StoreContext.for(@shop)

      <<~PROMPT
        You are a product query extractor for an e-commerce search engine.
        #{store_ctx.present? ? "\nStore context — use this to fill in implied fields when the user is vague:\n#{store_ctx}\n" : ""}
        Extract ONLY what is explicitly mentioned in the user message.
        When the user is vague (e.g. "show me something nice"), use the store category/niche above to infer a sensible product_type or keywords — but only if the store context is present.
        Do NOT infer other fields that are not stated.
        Return null for any field that is not mentioned.

        ## Output schema (return ONLY valid JSON, no explanation):

        {
          "product_name":  <string|null>,   // specific product name or partial name e.g. "Air Max 90", "iPhone 15 Pro", "probook 14", "MacBook Pro" — include even if only part of the name is mentioned
          "keywords":      <string|null>,   // general search terms e.g. "running shoes", "wireless headphones"
          "variant_name":  <string|null>,   // exact variant string e.g. "64GB Black", "Small Blue"
          "product_type":  <string|null>,   // product category e.g. "shoes", "laptop", "t-shirt", "bag"
          "vendor":        <string|null>,   // brand / manufacturer e.g. "Nike", "Apple", "Samsung"
          "collection":    <string|null>,   // store collection name e.g. "Summer Sale", "New Arrivals"
          "attributes": {
            "color":        <string|null>,  // e.g. "red", "navy blue", "multicolor"
            "size":         <string|null>,  // e.g. "XL", "10", "42", "1TB"
            "material":     <string|null>,  // e.g. "leather", "cotton", "stainless steel"
            "style":        <string|null>,  // e.g. "slim fit", "oversized", "casual", "formal"
            "connectivity": <string|null>,  // e.g. "wireless", "bluetooth", "USB-C"
            "storage":      <string|null>,  // e.g. "256GB", "1TB"
            "other":        <string|null>   // any other variant attribute mentioned
          },
          "price_range": {
            "min": <number|null>,           // minimum price in store currency
            "max": <number|null>            // maximum price in store currency
          },
          "gender":        <string|null>,   // "men", "women", "kids", "unisex" — only if stated
          "occasion":      <string|null>,   // e.g. "birthday", "wedding", "gym", "office", "casual"
          "gift_for":      <string|null>,   // gift recipient e.g. "mom", "boyfriend", "teenager"
          "in_stock":      <boolean|null>,  // true if user wants in-stock only, null otherwise
          "sort_by":       <string|null>    // "price_asc", "price_desc", "newest" — only if user says "cheapest", "most expensive", "latest" etc.
        }

        ## Examples:

        User: "Show me red Nike running shoes in size 10 under $150"
        Output:
        {
          "product_name": null,
          "keywords": "running shoes",
          "variant_name": null,
          "product_type": "shoes",
          "vendor": "Nike",
          "collection": null,
          "attributes": { "color": "red", "size": "10", "material": null, "style": null, "connectivity": null, "storage": null, "other": null },
          "price_range": { "min": null, "max": 150 },
          "gender": null,
          "occasion": null,
          "gift_for": null,
          "in_stock": null,
          "sort_by": null
        }

        User: "Do you have any wireless Bluetooth headphones with noise cancellation around $50 to $200?"
        Output:
        {
          "product_name": null,
          "keywords": "headphones noise cancellation",
          "variant_name": null,
          "product_type": "headphones",
          "vendor": null,
          "collection": null,
          "attributes": { "color": null, "size": null, "material": null, "style": null, "connectivity": "wireless bluetooth", "storage": null, "other": "noise cancellation" },
          "price_range": { "min": 50, "max": 200 },
          "gender": null,
          "occasion": null,
          "gift_for": null,
          "in_stock": null,
          "sort_by": null
        }

        User: "I need the cheapest black leather bag in stock for a woman"
        Output:
        {
          "product_name": null,
          "keywords": "bag",
          "variant_name": null,
          "product_type": "bag",
          "vendor": null,
          "collection": null,
          "attributes": { "color": "black", "size": null, "material": "leather", "style": null, "connectivity": null, "storage": null, "other": null },
          "price_range": { "min": null, "max": null },
          "gender": "women",
          "occasion": null,
          "gift_for": null,
          "in_stock": true,
          "sort_by": "price_asc"
        }

        User: "I want to buy the iPhone 15 Pro in 256GB Space Black"
        Output:
        {
          "product_name": "iPhone 15 Pro",
          "keywords": null,
          "variant_name": "256GB Space Black",
          "product_type": null,
          "vendor": "Apple",
          "collection": null,
          "attributes": { "color": "Space Black", "size": null, "material": null, "style": null, "connectivity": null, "storage": "256GB", "other": null },
          "price_range": { "min": null, "max": null },
          "gender": null,
          "occasion": null,
          "gift_for": null,
          "in_stock": null,
          "sort_by": null
        }

        User: "I need a birthday gift for my mom around $50"
        Output:
        {
          "product_name": null,
          "keywords": "gift",
          "variant_name": null,
          "product_type": null,
          "vendor": null,
          "collection": null,
          "attributes": { "color": null, "size": null, "material": null, "style": null, "connectivity": null, "storage": null, "other": null },
          "price_range": { "min": null, "max": 50 },
          "gender": null,
          "occasion": "birthday",
          "gift_for": "mom",
          "in_stock": null,
          "sort_by": null
        }

        Return ONLY the JSON. No markdown, no explanation.
      PROMPT
    end

    # ==================================================
    # PARSER
    # ==================================================
    def parse_response(response)
      JSON.parse(extract_json(response)).deep_symbolize_keys
    rescue
      {}
    end

    def extract_json(text)
      text.to_s.match(/\{.*\}/m)&.to_s || "{}"
    end

    # ==================================================
    # MODE 1: STATEFUL MERGE — carry forward previous values,
    # overwrite only the fields explicitly mentioned this turn.
    # ==================================================
    def merge_with_previous(new_data)
      base = deep_dup(@previous_data)

      # Scalar overrides — only update when the new message mentions them
      %i[product_name keywords variant_name product_type vendor collection gender occasion gift_for sort_by].each do |key|
        base[key] = new_data[key] if present?(new_data[key])
      end

      base[:in_stock] = new_data[:in_stock] unless new_data[:in_stock].nil?

      # Attributes — merge key-by-key so "now show it in blue" doesn't lose size
      base[:attributes] ||= empty_attributes
      if new_data[:attributes].is_a?(Hash)
        new_data[:attributes].each do |k, v|
          base[:attributes][k] = v if present?(v)
        end
      end

      # Price range — update only the bounds that are explicitly stated
      base[:price_range] ||= { min: nil, max: nil }
      if new_data[:price_range].is_a?(Hash)
        base[:price_range][:min] = new_data[:price_range][:min] if present?(new_data[:price_range][:min])
        base[:price_range][:max] = new_data[:price_range][:max] if present?(new_data[:price_range][:max])
      end

      base
    end

    # ==================================================
    # MODE 2: FRESH — clean slate from the new message
    # ==================================================
    def normalize_fresh(new_data)
      {
        product_name: new_data[:product_name],
        keywords:     new_data[:keywords],
        variant_name: new_data[:variant_name],
        product_type: new_data[:product_type],
        vendor:       new_data[:vendor],
        collection:   new_data[:collection],
        attributes:   normalize_attributes(new_data[:attributes]),
        price_range:  normalize_price(new_data[:price_range]),
        gender:       new_data[:gender],
        occasion:     new_data[:occasion],
        gift_for:     new_data[:gift_for],
        in_stock:     new_data[:in_stock],
        sort_by:      new_data[:sort_by]
      }
    end

    # ==================================================
    # HELPERS
    # ==================================================
    def normalize_attributes(attrs)
      base = empty_attributes
      return base unless attrs.is_a?(Hash)

      base.merge(attrs.slice(*base.keys))
    end

    def empty_attributes
      { color: nil, size: nil, material: nil, style: nil, connectivity: nil, storage: nil, other: nil }
    end

    def normalize_price(price)
      return { min: nil, max: nil } unless price.is_a?(Hash)

      { min: price[:min], max: price[:max] }
    end

    def present?(val)
      val.present?
    end

    def deep_dup(obj)
      Marshal.load(Marshal.dump(obj))
    rescue
      obj.dup
    end

    # ==================================================
    # FALLBACK — use raw message as keywords
    # ==================================================
    def fallback_response
      {
        product_name: nil,
        keywords:     @message,
        variant_name: nil,
        product_type: nil,
        vendor:       nil,
        collection:   nil,
        attributes:   empty_attributes,
        price_range:  { min: nil, max: nil },
        gender:       nil,
        occasion:     nil,
        gift_for:     nil,
        in_stock:     nil,
        sort_by:      nil
      }
    end
  end
end
