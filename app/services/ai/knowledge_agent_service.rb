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
          - Use ONLY the information explicitly stated in the Context section above.
          - Do NOT invent, infer, assume, or extrapolate any policy or detail not word-for-word in the Context.
          - If the Context does not contain a clear answer to the customer's question, do NOT guess.
            Instead respond with exactly: "I don't have that information. #{contact_line}"
          - Never expand beyond what the Context literally states.
        TEXT
      ).call
    end

    private

    def search_knowledge
      embedding = Ai::EmbeddingService.new.embed(@message)

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
      msg = "I'm sorry, I don't have information on that. #{contact_line}"
      @stream_callback&.call(msg)
      msg
    end

    def contact_line
      vr    = (@shop.ai_shopper_configuration&.visibility_rules || {}).with_indifferent_access
      email = vr[:support_email].presence
      phone = vr[:whatsapp].presence

      parts = []
      parts << "email us at **#{email}**" if email
      parts << "reach us on WhatsApp at **#{phone}**" if phone

      if parts.empty?
        'Please type "Human" to connect with our support team.'
      else
        "Please #{parts.join(" or ")} for further assistance, or type \"Human\" to connect with an agent."
      end
    end
  end
end
