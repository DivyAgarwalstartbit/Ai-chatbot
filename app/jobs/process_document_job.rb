# frozen_string_literal: true

# Processes an uploaded TrainingDocument file end-to-end:
#
#   1. Downloads the ActiveStorage attachment to a Tempfile
#   2. Extracts plain text via DocumentTextExtractionService
#   3. Saves the text to TrainingDocument#content
#      → the after_save callback on TrainingDocument automatically enqueues
#        DocumentChunkJob, which calls ChunkDocumentService
#   4. Updates processing_status throughout: pending → processing → processed
#      (or failed on error)
#
# This job is idempotent: re-running it on an already-processed document will
# re-extract and re-chunk (old chunks are deleted by ChunkDocumentService).
#
class ProcessDocumentJob < ApplicationJob
  queue_as :documents

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # @param document_id [Integer]
  def perform(document_id)
    document = TrainingDocument.find_by(id: document_id)

    unless document
      Rails.logger.warn("[ProcessDocumentJob] TrainingDocument ##{document_id} not found, discarding.")
      return
    end

    unless document.file.attached?
      Rails.logger.warn("[ProcessDocumentJob] TrainingDocument ##{document_id} has no attached file, skipping.")
      mark_failed!(document, "No file attached.")
      return
    end

    mark_processing!(document)

    text = extract_text(document)

    if text.nil?
      # extract_text already called mark_failed!
      return
    end

    # Saving content triggers the after_save → DocumentChunkJob automatically.
    document.update!(
      content:           text,
      processing_status: "processed",
      processing_error:  nil
    )

    Rails.logger.info(
      "[ProcessDocumentJob] Document ##{document_id} processed: " \
      "#{text.split.size} words → chunking enqueued."
    )
  end

  private

  def extract_text(document)
    # Stream the blob to a Tempfile so pdf-reader / docx can open it by path.
    result = download_to_tempfile(document.file) do |tmpfile|
      # Wrap in an UploadedFile-like object so DocumentTextExtractionService
      # can call .content_type, .size, .path, .original_filename, .read.
      proxy = FileProxy.new(
        path:             tmpfile.path,
        content_type:     document.file.content_type,
        size:             document.file.byte_size,
        original_filename: document.file.filename.to_s
      )
      DocumentTextExtractionService.new(proxy).call
    end

    if result.success?
      result.text
    else
      Rails.logger.error("[ProcessDocumentJob] Extraction failed for ##{document.id}: #{result.error}")
      mark_failed!(document, result.error)
      nil
    end
  rescue => e
    Rails.logger.error("[ProcessDocumentJob] Unexpected error for ##{document.id}: #{e.class} #{e.message}")
    mark_failed!(document, "#{e.class}: #{e.message}")
    raise  # re-raise so retry_on can handle it
  end

  # Downloads an ActiveStorage blob to a Tempfile, yields it, then cleans up.
  def download_to_tempfile(attachment, &block)
    ext = File.extname(attachment.filename.to_s)
    Tempfile.create(["process_document", ext]) do |tmpfile|
      tmpfile.binmode
      attachment.download { |chunk| tmpfile.write(chunk) }
      tmpfile.flush
      tmpfile.rewind
      block.call(tmpfile)
    end
  end

  def mark_processing!(document)
    document.update_columns(processing_status: "processing", processing_error: nil)
  end

  def mark_failed!(document, message)
    document.update_columns(
      processing_status: "failed",
      processing_error:  message.to_s.truncate(500)
    )
  end

  # Minimal struct that satisfies the interface DocumentTextExtractionService expects:
  #   .content_type, .size, .path, .original_filename, .read
  FileProxy = Struct.new(:path, :content_type, :size, :original_filename, keyword_init: true) do
    def read
      File.binread(path)
    end
  end
end
