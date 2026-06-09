# frozen_string_literal: true

# Orchestrates the FAQ import pipeline for both pasted text and uploaded files.
#
# Input: either a raw text string (paste flow) or an uploaded file (upload flow).
# Steps:
#   1. If file given → DocumentTextExtractionService extracts plain text
#   2. Passes text → Ai::FaqGenerationService generates FAQ pairs
#   3. Returns a Result with the FAQ array or an error string
#
# Usage:
#   # Paste flow
#   result = FaqImportService.new(text: "Return policy: ...").call
#
#   # Upload flow
#   result = FaqImportService.new(file: params[:faq_import][:file]).call
#
#   result.success?  # => true / false
#   result.faqs      # => [{ "question" => "...", "answer" => "..." }, ...]
#   result.error     # => nil or human-readable String
#
class FaqImportService
  Result = Struct.new(:faqs, :error, keyword_init: true) do
    def success? = error.nil?
  end

  def initialize(text: nil, file: nil)
    @text = text
    @file = file
  end

  def call
    text_result = resolve_text
    return Result.new(faqs: nil, error: text_result.error) unless text_result.success?

    generation_result = Ai::FaqGenerationService.new(text_result.text).call

    unless generation_result.success?
      return Result.new(faqs: nil, error: generation_result.error)
    end

    if generation_result.faqs.empty?
      return Result.new(
        faqs:  [],
        error: "The AI could not find any FAQ-worthy content in the provided text. " \
               "Try adding more detailed store content."
      )
    end

    Result.new(faqs: generation_result.faqs, error: nil)
  end

  private

  # Returns a simple duck-typed result with #success? and #text / #error.
  def resolve_text
    if @text.present?
      OpenStruct.new(success?: true, text: @text.strip, error: nil)
    elsif @file.present?
      DocumentTextExtractionService.new(@file).call
    else
      OpenStruct.new(success?: false, text: nil, error: "Please paste some text or upload a file.")
    end
  end
end
