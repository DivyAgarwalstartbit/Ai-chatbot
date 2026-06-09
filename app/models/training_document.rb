class TrainingDocument < ApplicationRecord
  belongs_to :shop
  has_many :document_chunks, dependent: :delete_all

  has_one_attached :file

  # ── Processing status ──────────────────────────────────────────────────────
  # Tracks text extraction + chunking (the first half of the indexing pipeline).
  #
  # pending    → just created, not yet processed
  # processing → text extraction / chunking in progress
  # processed  → text extracted, chunks stored
  # failed     → text extraction or chunking failed (see processing_error)

  STATUSES = %w[pending processing processed failed].freeze

  scope :pending_processing,  -> { where(processing_status: "pending") }
  scope :processing,          -> { where(processing_status: "processing") }
  scope :processed,           -> { where(processing_status: "processed") }
  scope :failed_processing,   -> { where(processing_status: "failed") }

  def pending?    = processing_status == "pending"
  def processing? = processing_status == "processing"
  def processed?  = processing_status == "processed"
  def failed?     = processing_status == "failed"

  # ── Embedding status ───────────────────────────────────────────────────────
  # Tracks the second half of the indexing pipeline: generating pgvector
  # embeddings for each document_chunk.
  #
  # pending    → chunks exist but embedding has not started
  # processing → GenerateEmbeddingsJob is running
  # completed  → all chunks have been embedded
  # failed     → embedding failed (see embedding_error)

  EMBEDDING_STATUSES = %w[pending processing completed failed].freeze

  scope :embedding_pending,    -> { where(embedding_status: "pending") }
  scope :embedding_processing, -> { where(embedding_status: "processing") }
  scope :embedding_completed,  -> { where(embedding_status: "completed") }
  scope :embedding_failed,     -> { where(embedding_status: "failed") }

  def embedding_pending?    = embedding_status == "pending"
  def embedding_processing? = embedding_status == "processing"
  def embedding_completed?  = embedding_status == "completed"
  def embedding_failed?     = embedding_status == "failed"

  # True when this document is fully indexed and ready for vector search.
  def indexed? = embedding_completed?

  # ── File validation ────────────────────────────────────────────────────────

  UPLOADABLE_CONTENT_TYPES = %w[
    application/pdf
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    text/plain
  ].freeze

  validate :acceptable_file, if: -> { file.attached? }

  # ── Source types ───────────────────────────────────────────────────────────
  # source_type is a space-separated string that may contain any combination of:
  #   manual_entry | shopify_sync | uploaded_document

  SOURCE_TYPES = %w[manual_entry shopify_sync uploaded_document].freeze

  # ── Callbacks ─────────────────────────────────────────────────────────────
  #
  # Both content paths that feed the vector index trigger the same pipeline:
  #
  #   content change  (manual entry, FAQ, extracted document text)
  #     → DocumentChunkJob → ChunkDocumentService → GenerateEmbeddingsJob
  #
  #   shopify_content change  (Shopify policy sync)
  #     → DocumentChunkJob → ChunkDocumentService → GenerateEmbeddingsJob
  #       (DocumentChunkJob merges content + shopify_content before chunking)

  after_save :enqueue_chunking, if: :should_rechunk?

  private

  # Re-chunk (and re-embed) whenever the searchable text content changes.
  # For policy documents both the manual content and the Shopify-synced content
  # feed the vector index, so a change to either triggers the pipeline.
  def should_rechunk?
    saved_change_to_content? || saved_change_to_shopify_content?
  end

  def enqueue_chunking
    DocumentChunkJob.perform_later(id)
  end

  def acceptable_file
    unless UPLOADABLE_CONTENT_TYPES.include?(file.content_type)
      errors.add(:file, "must be a PDF, DOCX, or TXT file")
    end

    if file.byte_size > 10.megabytes
      errors.add(:file, "must be smaller than 10 MB")
    end
  end
end
