class DocumentChunk < ApplicationRecord
 belongs_to :source,
 polymorphic: true,
 optional: true


  belongs_to :shop
  belongs_to :training_document

  has_neighbors :embedding

  validates :chunk_index, presence: true, uniqueness: { scope: :training_document_id }
  validates :content, presence: true

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
end
