# frozen_string_literal: true

# Extracts plain text from uploaded files (PDF, DOCX, TXT) or returns
# pasted text directly.
#
# Usage:
#   # From an uploaded file (ActionDispatch::Http::UploadedFile)
#   result = FaqExtractionService.new(file: params[:file]).call
#   result.text    # => "extracted text..."
#   result.error   # => nil on success, String on failure
#
#   # From pasted text
#   result = FaqExtractionService.new(text: params[:text]).call
#
class FaqExtractionService
  Result = Struct.new(:text, :error, keyword_init: true) do
    def success? = error.nil?
  end

  SUPPORTED_TYPES = %w[
    application/pdf
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    text/plain
  ].freeze

  MAX_BYTES = 10.megabytes

  def initialize(file: nil, text: nil)
    @file = file
    @text = text
  end

  def call
    if @text.present?
      return Result.new(text: @text.strip, error: nil)
    end

    return Result.new(text: nil, error: "No file or text provided.") if @file.nil?

    validate_file.tap { |r| return r if r } # returns early on validation error

    extract_from_file
  end

  private

  def validate_file
    unless SUPPORTED_TYPES.include?(@file.content_type)
      return Result.new(text: nil, error: "Unsupported file type. Please upload a PDF, DOCX, or TXT file.")
    end

    if @file.size > MAX_BYTES
      return Result.new(text: nil, error: "File is too large. Maximum size is 10 MB.")
    end

    nil
  end

  def extract_from_file
    text = case @file.content_type
           when "application/pdf"
             extract_pdf
           when "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
             extract_docx
           when "text/plain"
             @file.read.force_encoding("UTF-8").scrub
           end

    text = text.to_s.strip

    if text.blank?
      return Result.new(text: nil, error: "Could not extract any text from the file. The file may be empty or image-based.")
    end

    Result.new(text: text, error: nil)
  rescue => e
    Rails.logger.error("[FaqExtractionService] Extraction failed: #{e.class}: #{e.message}")
    Result.new(text: nil, error: "Failed to read the file. Please check it is not corrupted.")
  end

  def extract_pdf
    reader = PDF::Reader.new(@file.path)
    reader.pages.map(&:text).join("\n\n")
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
    raise "PDF could not be read: #{e.message}"
  end

  def extract_docx
    doc = Docx::Document.open(@file.path)
    doc.paragraphs.map(&:to_s).reject(&:blank?).join("\n\n")
  rescue => e
    raise "DOCX could not be read: #{e.message}"
  end
end
