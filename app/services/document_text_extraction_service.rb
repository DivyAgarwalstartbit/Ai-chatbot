# frozen_string_literal: true

# Extracts plain text from an uploaded file (PDF, DOCX, or TXT).
# This service is file-only — for pasted text pass it directly to
# Ai::FaqGenerationService or FaqImportService.
#
# Usage:
#   result = DocumentTextExtractionService.new(file).call
#   result.text    # => "extracted text..." (nil on failure)
#   result.error   # => nil on success, human-readable String on failure
#   result.success? # => true / false
#
class DocumentTextExtractionService
  Result = Struct.new(:text, :error, keyword_init: true) do
    def success? = error.nil?
  end

  SUPPORTED_CONTENT_TYPES = %w[
    application/pdf
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    text/plain
  ].freeze

  SUPPORTED_EXTENSIONS = %w[.pdf .docx .txt].freeze

  MAX_BYTES = 10.megabytes

  def initialize(file)
    @file = file
  end

  def call
    error = validate
    return Result.new(text: nil, error: error) if error

    extract
  end

  private

  def validate
    return "No file provided." if @file.nil?

    content_type = @file.content_type.to_s.split(";").first.strip

    unless SUPPORTED_CONTENT_TYPES.include?(content_type)
      ext = File.extname(@file.original_filename.to_s).downcase
      unless SUPPORTED_EXTENSIONS.include?(ext)
        return "Unsupported file type "#{@file.original_filename}". Please upload a PDF, DOCX, or TXT file."
      end
      # Fallback: trust extension when content-type is ambiguous (e.g. octet-stream)
    end

    if @file.size > MAX_BYTES
      return "File is too large (#{(@file.size / 1.megabyte.to_f).round(1)} MB). Maximum allowed size is 10 MB."
    end

    nil
  end

  def extract
    content_type = @file.content_type.to_s.split(";").first.strip
    ext          = File.extname(@file.original_filename.to_s).downcase

    text = if content_type == "application/pdf" || ext == ".pdf"
             extract_pdf
           elsif content_type.include?("wordprocessingml") || ext == ".docx"
             extract_docx
           else
             extract_txt
           end

    text = text.to_s.strip

    if text.blank?
      return Result.new(
        text:  nil,
        error: "The file appears to be empty or contains no extractable text. " \
               "Image-based PDFs are not supported — please use a text-based PDF."
      )
    end

    Result.new(text: text, error: nil)
  rescue => e
    Rails.logger.error("[DocumentTextExtractionService] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    Result.new(text: nil, error: "Could not read the file. Please check it is not corrupted and try again.")
  end

  def extract_pdf
    reader = PDF::Reader.new(@file.path)
    reader.pages.map(&:text).join("\n\n")
  rescue PDF::Reader::MalformedPDFError => e
    raise "Malformed PDF: #{e.message}"
  rescue PDF::Reader::UnsupportedFeatureError => e
    raise "PDF uses unsupported features: #{e.message}"
  end

  def extract_docx
    doc = Docx::Document.open(@file.path)
    doc.paragraphs.map(&:to_s).reject(&:blank?).join("\n\n")
  rescue => e
    raise "DOCX could not be read: #{e.message}"
  end

  def extract_txt
    @file.read.force_encoding("UTF-8").scrub
  end
end
