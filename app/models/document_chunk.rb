class DocumentChunk < ApplicationRecord
 belongs_to :source,
 polymorphic: true,
 optional: true


  belongs_to :shop
  belongs_to :training_document, optional: true

  has_neighbors :embedding

  validates :chunk_index, presence: true
  validates :chunk_index,
            uniqueness: { scope: :training_document_id },
            if: -> { training_document_id.present? }
  validates :chunk_index,
            uniqueness: { scope: %i[source_type source_id] },
            if: -> { source_type.present? && source_id.present? }
  validates :content, presence: true
  validate :source_or_training_document_present

  default_scope { order(:chunk_index) }

  # ── Embedding scopes ───────────────────────────────────────────────────────

  # Chunks that have never been embedded (embedding column is NULL).
  scope :without_embedding, -> { where(embedding: nil) }

  # Chunks that have a valid embedding vector.
  scope :with_embedding, -> { where.not(embedding: nil) }

  # Chunks embedded within a given time window — useful for auditing freshness.
  scope :embedded_after,  ->(time) { where("embedded_at > ?", time) }
  scope :embedded_before, ->(time) { where("embedded_at < ?", time) }

  # ── Helpers ────────────────────────────────────────────────────────────────

  def embedded?
    embedding.present?
  end

  private

  def source_or_training_document_present
    return if training_document_id.present? || source.present?

    errors.add(:base, "must belong to a training document or source")
  end
end
