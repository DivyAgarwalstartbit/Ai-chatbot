# frozen_string_literal: true

# Splits a TrainingDocument's content into overlapping word-bounded chunks,
# respecting paragraph boundaries where possible, then persists them to
# document_chunks. Old chunks are deleted before new ones are inserted.
#
# Usage:
#   ChunkDocumentService.new(training_document).call
#
class ChunkDocumentService
  # Target chunk size in words. Chunks stay within [MIN_WORDS, MAX_WORDS].
  TARGET_WORDS = 700
  MIN_WORDS    = 500
  MAX_WORDS    = 1000

  def initialize(document)
    @document = document
  end

  def call
    content = @document.content.to_s.strip
    return 0 if content.blank?

    chunks = split(content)
    persist(chunks)
    chunks.size
  end

  private

  # ---------------------------------------------------------------------------
  # Splitting
  # ---------------------------------------------------------------------------

  # Split content into paragraphs first, then merge/split paragraphs to hit
  # the target word count.
  def split(content)
    paragraphs = content
                   .split(/\n{2,}/)          # split on blank lines
                   .map(&:strip)
                   .reject(&:blank?)

    chunks  = []
    buffer  = []
    buf_words = 0

    paragraphs.each do |para|
      para_words = word_count(para)

      # Single paragraph already exceeds MAX — hard-split it by sentences.
      if para_words > MAX_WORDS
        # Flush existing buffer first.
        chunks << buffer.join("\n\n") if buffer.any?
        buffer    = []
        buf_words = 0

        chunks.concat(split_large_paragraph(para))
        next
      end

      # Adding this paragraph would exceed MAX — flush first.
      if buf_words + para_words > MAX_WORDS && buf_words >= MIN_WORDS
        chunks << buffer.join("\n\n")
        buffer    = []
        buf_words = 0
      end

      buffer    << para
      buf_words += para_words

      # If we've hit the target range, flush.
      if buf_words >= TARGET_WORDS
        chunks << buffer.join("\n\n")
        buffer    = []
        buf_words = 0
      end
    end

    # Flush remainder.
    if buffer.any?
      if chunks.any? && buf_words < MIN_WORDS
        # Merge small tail into last chunk to avoid tiny orphan.
        chunks[-1] = "#{chunks[-1]}\n\n#{buffer.join("\n\n")}"
      else
        chunks << buffer.join("\n\n")
      end
    end

    chunks.map(&:strip).reject(&:blank?)
  end

  # Split an oversized paragraph by sentences, grouping sentences until we
  # approach TARGET_WORDS.
  def split_large_paragraph(para)
    # Naive sentence split on ". ", "! ", "? " followed by a capital letter.
    sentences = para.split(/(?<=[.!?])\s+(?=[A-Z\"\'])/)
    chunks    = []
    buffer    = []
    buf_words = 0

    sentences.each do |sentence|
      s_words = word_count(sentence)

      if buf_words + s_words > MAX_WORDS && buf_words >= MIN_WORDS
        chunks << buffer.join(" ")
        buffer    = []
        buf_words = 0
      end

      buffer    << sentence
      buf_words += s_words

      if buf_words >= TARGET_WORDS
        chunks << buffer.join(" ")
        buffer    = []
        buf_words = 0
      end
    end

    chunks << buffer.join(" ") if buffer.any?
    chunks.map(&:strip).reject(&:blank?)
  end

  def word_count(text)
    text.split.size
  end

  # ---------------------------------------------------------------------------
  # Persistence
  # ---------------------------------------------------------------------------

  def persist(chunks)
    ActiveRecord::Base.transaction do
      @document.document_chunks.delete_all

      rows = chunks.each_with_index.map do |text, idx|
        {
          training_document_id: @document.id,
          shop_id:              @document.shop_id,
          source_type:          "TrainingDocument",
          source_id:            @document.id,
          content:              text,
          chunk_index:          idx,
          created_at:           Time.current,
          updated_at:           Time.current
        }
      end

      DocumentChunk.insert_all!(rows) if rows.any?
    end
  end
end
