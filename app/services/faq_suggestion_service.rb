# frozen_string_literal: true

# Gathers all knowledge-base content for a shop, sends it to the AI, and
# returns de-duplicated FAQ suggestions.
#
# Knowledge sources (in priority order):
#   1. Shipping Policy   — training_documents.content  (manual)
#   2. Shipping Policy   — training_documents.shopify_content (synced)
#   3. Return Policy     — same pattern
#   4. Uploaded Documents — training_documents.content (extracted text)
#
# De-duplication:
#   Generated questions are compared case-insensitively against the shop's
#   existing FAQ titles. Near-duplicates (>80% word overlap) are also filtered.
#
# Usage:
#   result = FaqSuggestionService.new(shop).call
#   result.success?    # => true / false
#   result.suggestions # => [{ "question" => "...", "answer" => "..." }, ...]
#   result.error       # => nil or human-readable String
#
class FaqSuggestionService
  Result = Struct.new(:suggestions, :error, keyword_init: true) do
    def success? = error.nil?
  end

  # Character ceiling for context sent to the AI (keeps latency and cost low)
  MAX_CONTEXT_CHARS = 15_000

  def initialize(shop)
    @shop = shop
  end

  def call
    context = build_context
    return Result.new(suggestions: [], error: context[:error]) if context[:error]
    return Result.new(suggestions: [], error: "No knowledge base content found. Add a shipping policy, return policy, or upload documents first.") if context[:text].blank?

    generation_result = Ai::FaqGenerationService.new(context[:text]).call
    return Result.new(suggestions: [], error: generation_result.error) unless generation_result.success?

    filtered = deduplicate(generation_result.faqs)

    Result.new(suggestions: filtered, error: nil)
  end

  private

  # ── Context building ─────────────────────────────────────────────────────

  def build_context
    sections = []

    # Shipping policy
    shipping = policy_for("shipping_policy")
    if shipping
      text = [shipping.content.presence, shipping.shopify_content.presence].compact.join("\n\n")
      sections << "=== Shipping Policy ===\n#{text}" if text.present?
    end

    # Return policy
    returns = policy_for("return_policy")
    if returns
      text = [returns.content.presence, returns.shopify_content.presence].compact.join("\n\n")
      sections << "=== Return Policy ===\n#{text}" if text.present?
    end

    # Uploaded documents (extracted text stored in content)
    uploaded = @shop.training_documents
                    .where(document_type: "uploaded_document")
                    .where.not(content: [nil, ""])
                    .order(created_at: :desc)
                    .limit(5)

    uploaded.each do |doc|
      sections << "=== Document: #{doc.title.presence || "Uploaded File"} ===\n#{doc.content}"
    end

    return { error: nil, text: nil } if sections.empty?

    combined = sections.join("\n\n")
    # Truncate to MAX_CONTEXT_CHARS from the start to preserve most important content
    truncated = combined.length > MAX_CONTEXT_CHARS ? combined[0, MAX_CONTEXT_CHARS] : combined

    { error: nil, text: truncated }
  rescue => e
    Rails.logger.error("[FaqSuggestionService] Context build error: #{e.class} #{e.message}")
    { error: "Could not gather knowledge base content. Please try again.", text: nil }
  end

  def policy_for(document_type)
    @shop.training_documents.find_by(document_type: document_type)
  end

  # ── De-duplication ───────────────────────────────────────────────────────

  def deduplicate(suggestions)
    existing_questions = @shop.training_documents
                              .where(document_type: "faq")
                              .pluck(:title)
                              .map { |q| normalize(q) }

    suggestions.reject do |suggestion|
      candidate = normalize(suggestion["question"])
      existing_questions.any? { |eq| similar?(candidate, eq) }
    end
  end

  # Lowercase, strip punctuation, collapse whitespace
  def normalize(text)
    text.to_s.downcase.gsub(/[^a-z0-9\s]/, "").squeeze(" ").strip
  end

  # True if the two questions share >75% of their words (bag-of-words overlap)
  def similar?(a, b)
    return true if a == b

    words_a = a.split.to_set
    words_b = b.split.to_set
    return false if words_a.empty? || words_b.empty?

    intersection = (words_a & words_b).size
    shorter      = [words_a.size, words_b.size].min

    (intersection.to_f / shorter) > 0.75
  end
end
