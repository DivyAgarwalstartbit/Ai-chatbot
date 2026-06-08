# frozen_string_literal: true

namespace :embeddings do
  # ── kb:embeddings:backfill ────────────────────────────────────────────────
  #
  # Enqueues GenerateEmbeddingsJob for every TrainingDocument that has chunks
  # but is missing embeddings on one or more of those chunks.
  #
  # Safe to run multiple times — documents whose chunks are already fully
  # embedded are skipped.
  #
  # Usage:
  #   bin/rails embeddings:backfill
  #   bin/rails embeddings:backfill[dry_run]   # print counts, enqueue nothing
  #
  desc "Backfill embeddings for all un-embedded document chunks"
  task :backfill, [:mode] => :environment do |_task, args|
    dry_run = args[:mode].to_s.downcase == "dry_run"

    puts dry_run ? "[DRY RUN] No jobs will be enqueued." : "Enqueuing embedding jobs..."

    # Find every document that has at least one chunk without an embedding.
    doc_ids = DocumentChunk
                .without_embedding
                .unscoped
                .distinct
                .pluck(:training_document_id)

    if doc_ids.empty?
      puts "All chunks are already embedded. Nothing to do."
      next
    end

    docs = TrainingDocument.where(id: doc_ids).order(:id)

    puts "Found #{docs.size} document(s) with un-embedded chunks:"
    docs.each do |doc|
      total    = doc.document_chunks.count
      missing  = doc.document_chunks.without_embedding.count
      puts "  ##{doc.id} [#{doc.document_type}] #{doc.title.presence || '(untitled)'} — #{missing}/#{total} chunks missing embeddings"
    end

    unless dry_run
      docs.each do |doc|
        # Reset embedding_status so the job starts cleanly.
        doc.update_columns(embedding_status: "pending", embedding_error: nil)
        GenerateEmbeddingsJob.perform_later(doc.id)
      end
      puts "\nEnqueued #{docs.size} GenerateEmbeddingsJob(s)."
    end
  end

  # ── kb:embeddings:status ──────────────────────────────────────────────────
  #
  # Prints a summary of embedding status across all TrainingDocuments.
  #
  # Usage:
  #   bin/rails embeddings:status
  #
  desc "Print embedding status summary for all training documents"
  task status: :environment do
    counts = TrainingDocument.group(:embedding_status).count

    puts "\n=== Embedding Status Summary ==="
    %w[pending processing completed failed].each do |status|
      n = counts[status] || 0
      puts "  #{status.ljust(12)}: #{n}"
    end

    total_chunks    = DocumentChunk.count
    embedded_chunks = DocumentChunk.with_embedding.count
    missing_chunks  = total_chunks - embedded_chunks

    puts "\n=== Chunk Coverage ==="
    puts "  Total chunks    : #{total_chunks}"
    puts "  Embedded        : #{embedded_chunks}"
    puts "  Missing embedding: #{missing_chunks}"
    puts ""
  end

  # ── kb:embeddings:retry_failed ────────────────────────────────────────────
  #
  # Re-enqueues GenerateEmbeddingsJob for all documents in embedding_status=failed.
  #
  # Usage:
  #   bin/rails embeddings:retry_failed
  #
  desc "Re-enqueue embedding jobs for all documents in failed state"
  task retry_failed: :environment do
    failed = TrainingDocument.embedding_failed

    if failed.empty?
      puts "No documents in failed embedding state."
      next
    end

    puts "Re-enqueuing #{failed.size} failed document(s):"
    failed.each do |doc|
      puts "  ##{doc.id} [#{doc.document_type}] #{doc.title.presence || '(untitled)'} — #{doc.embedding_error.to_s.truncate(80)}"
      doc.update_columns(embedding_status: "pending", embedding_error: nil)
      GenerateEmbeddingsJob.perform_later(doc.id)
    end
    puts "Done."
  end
end
