module Ai
  class KnowledgeAgentService
    # Chunks are re-ranked after vector search so that Shopify-synced content
    # always beats uploaded documents, which always beat manual entries.
    SOURCE_PRIORITY = {
      "shopify_sync"      => 0,
      "uploaded_document" => 1,
      "manual_entry"      => 2
    }.freeze

    def initialize(shop:, message:, memory: "", stream_callback: nil)
      @shop            = shop
      @message         = message
      @memory          = memory
      @stream_callback = stream_callback
    end

    def call
      chunks = search_knowledge

      return no_information if chunks.empty?

      Rails.logger.info("FOUND CHUNKS => #{chunks.count}")
      Ai::ChatGenerationService.new(
        message:         @message,
        context:         chunks.map(&:content).join("\n\n"),
        shop:            @shop,
        stream_callback: @stream_callback,
        instructions:    <<~TEXT
          You are answering store policy and support questions.
          - Use ONLY the provided store knowledge.
          - Answer return, shipping, and FAQ questions accurately.
          - Do not invent or assume policies not present in the context.
        TEXT
      ).call
    end

    private

    def search_knowledge
      embedding = Ai::OllamaEmbeddingService.new(@message).call

      # Fetch more candidates than needed so re-ranking has enough to work with.
      # includes(:training_document) avoids N+1 when reading source_type below.
      chunks = DocumentChunk
        .includes(:training_document)
        .where(shop_id: @shop.id, source_type: "TrainingDocument")
        .nearest_neighbors(:embedding, embedding, distance: "cosine")
        .limit(15)
        .to_a

      # Re-rank: shopify_sync first, then uploaded_document, then manual_entry.
      # Within the same tier, preserve the semantic similarity order.
      chunks
        .sort_by { |c|
          src_type = c.training_document&.source_type.to_s
          [ SOURCE_PRIORITY.fetch(src_type, 3), c.neighbor_distance ]
        }
        .first(5)
    rescue StandardError => e
      Rails.logger.error("KnowledgeAgentService#search_knowledge: #{e.class} #{e.message}")
      []
    end

    def no_information
      Ai::ChatGenerationService.new(
        message:         @message,
        shop:            @shop,
        stream_callback: @stream_callback,
        instructions:    <<~TEXT
          Tell the customer politely that this store information is not available yet.
          Ask them to contact support directly if they need further assistance or type "Human" to connect with Human support agent.
        TEXT
      ).call
    end
  end
end
