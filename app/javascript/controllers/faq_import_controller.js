import { Controller } from "@hotwired/stimulus"

// Controls the FAQ import panel UI:
//   - Tab switching (Paste Text / Upload Document)
//   - Syncing s-text-area value → hidden input before paste form submit
//   - Validating a file is chosen before upload form submit
//   - Loading state while the AI generates FAQs
//   - Restoring button state when an error Turbo Stream arrives
//   - Close / cancel behaviour
export default class extends Controller {
  static targets = [
    "pastePanel",
    "uploadPanel",
    "pasteTabBtn",
    "uploadTabBtn",
    "textArea",
    "generateBtn",
    "uploadBtn",
    "loadingIndicator",
    "loadingText",
    "errorBanner",
    "inputPanel",
    "previewPanel",
  ]

  static values = {
    shop: String,
    host: String,
    resetUrl: String,
  }

  connect() {
    this._activeTab = "paste"
    // Re-enable buttons if an error Turbo Stream replaces the error div
    // (the stream also runs an inline script, but this guards against races)
    this._observer = new MutationObserver(() => this._maybeStopLoading())
    const errorEl = document.getElementById("faq_import_error")
    if (errorEl) this._observer.observe(errorEl, { childList: true, subtree: true })
  }

  disconnect() {
    this._observer?.disconnect()
  }

  // ── Tab switching ────────────────────────────────────────────────────────

  showPasteTab(e) {
    e.preventDefault()
    this._setTab("paste")
  }

  showUploadTab(e) {
    e.preventDefault()
    this._setTab("upload")
  }

  _setTab(tab) {
    this._activeTab = tab
    const isPaste = tab === "paste"

    if (this.hasPastePanelTarget)  this.pastePanelTarget.style.display  = isPaste ? "" : "none"
    if (this.hasUploadPanelTarget) this.uploadPanelTarget.style.display = isPaste ? "none" : ""

    if (this.hasPasteTabBtnTarget) {
      this.pasteTabBtnTarget.setAttribute("variant", isPaste ? "primary" : "tertiary")
    }
    if (this.hasUploadTabBtnTarget) {
      this.uploadTabBtnTarget.setAttribute("variant", isPaste ? "tertiary" : "primary")
    }

    if (this.hasGenerateBtnTarget) this.generateBtnTarget.style.display = isPaste ? "" : "none"
    if (this.hasUploadBtnTarget)   this.uploadBtnTarget.style.display   = isPaste ? "none" : ""

    // Clear errors when switching tabs
    this._clearError()
  }

  // ── Unified submit (bound to the single "Generate FAQs" area button) ────

  submitActive(e) {
    e.preventDefault()
    if (this._activeTab === "upload") {
      this._submitUpload()
    } else {
      this._submitPaste()
    }
  }

  // ── Paste submit ─────────────────────────────────────────────────────────

  _submitPaste() {
    const ta     = document.getElementById("faq_import_text_area")
    const hidden = document.getElementById("faq_import_text_hidden")
    if (ta && hidden) hidden.value = ta.value || ""

    if (!hidden || hidden.value.trim() === "") {
      this._showError("Please paste some content before generating FAQs.")
      return
    }

    this._startLoading("Analysing content and generating FAQs…")
    document.getElementById("faq_import_paste_form").requestSubmit()
  }

  // Legacy target for data-action="click->faq-import#submitPaste" if used anywhere
  submitPaste(e) {
    if (e) e.preventDefault()
    this._submitPaste()
  }

  // ── Upload submit ─────────────────────────────────────────────────────────

  _submitUpload() {
    const input = document.querySelector(
      '[data-faq-import-target="uploadPanel"] input[type="file"]'
    )
    if (!input || !input.files || input.files.length === 0) {
      this._showError("Please choose a file before generating FAQs.")
      return
    }

    const file = input.files[0]
    const allowed = ["application/pdf",
                     "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                     "text/plain"]
    const ext = file.name.split(".").pop().toLowerCase()
    const allowedExts = ["pdf", "docx", "txt"]

    if (!allowed.includes(file.type) && !allowedExts.includes(ext)) {
      this._showError(`"${file.name}" is not supported. Please upload a PDF, DOCX, or TXT file.`)
      return
    }

    if (file.size > 10 * 1024 * 1024) {
      this._showError(`"${file.name}" is too large. Maximum file size is 10 MB.`)
      return
    }

    this._startLoading(`Extracting text from "${file.name}" and generating FAQs…`)
    document.getElementById("faq_import_upload_form").requestSubmit()
  }

  // Called by the file-upload controller's submit button (data-faq-import-target="uploadBtn")
  submitUpload(e) {
    if (e) e.preventDefault()
    this._submitUpload()
  }

  submitImport(e) {
    if (e) e.preventDefault()
    this._syncReviewRows()
    this.element.querySelector("form")?.requestSubmit()
  }

  selectAll(e) {
    if (e) e.preventDefault()
    this._setReviewSelection(true)
  }

  deselectAll(e) {
    if (e) e.preventDefault()
    this._setReviewSelection(false)
  }

  removeRow(e) {
    e.preventDefault()
    e.currentTarget.closest(".faq-preview-row")?.remove()
    this._updateSelectedCount()
  }

  updateSelectedCount() {
    this._updateSelectedCount()
  }

  // Called by Turbo form submit event (data-action="submit->faq-import#submitExtract")
  submitExtract(_e) {
    // Loading already started by _submitPaste / _submitUpload.
    // This is a safety net in case the form is submitted another way.
  }

  // ── Loading state ────────────────────────────────────────────────────────

  _startLoading(message = "Generating FAQs…") {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.style.display = ""
      if (this.hasLoadingTextTarget) this.loadingTextTarget.textContent = message
    }
    if (this.hasGenerateBtnTarget) this.generateBtnTarget.setAttribute("disabled", "")
    if (this.hasUploadBtnTarget)   this.uploadBtnTarget.setAttribute("disabled", "")
    this._clearError()
    this._isLoading = true
  }

  _stopLoading() {
    if (this.hasLoadingIndicatorTarget) this.loadingIndicatorTarget.style.display = "none"
    if (this.hasGenerateBtnTarget) this.generateBtnTarget.removeAttribute("disabled")
    if (this.hasUploadBtnTarget)   this.uploadBtnTarget.removeAttribute("disabled")
    this._isLoading = false
  }

  // Called by the inline <script> in extract_error.turbo_stream.erb
  stopLoading() {
    this._stopLoading()
  }

  _maybeStopLoading() {
    // If an error banner appeared and we're still in loading state, stop loading
    const errorEl = document.getElementById("faq_import_error")
    if (this._isLoading && errorEl && errorEl.children.length > 0) {
      this._stopLoading()
    }
  }

  // ── Error ────────────────────────────────────────────────────────────────

  _showError(message) {
    const errorEl = document.getElementById("faq_import_error")
    if (!errorEl && !this.hasErrorBannerTarget) return

    const target = errorEl || this.errorBannerTarget
    target.innerHTML = `
      <s-banner tone="critical">
        <s-paragraph>${message}</s-paragraph>
      </s-banner>
    `
  }

  _clearError() {
    const errorEl = document.getElementById("faq_import_error")
    if (errorEl) errorEl.innerHTML = ""
    else if (this.hasErrorBannerTarget) this.errorBannerTarget.innerHTML = ""
  }

  _syncReviewRows() {
    this.element.querySelectorAll(".faq-preview-row").forEach(row => {
      const idx = row.dataset.idx
      const qField  = document.getElementById("faq_q_field_" + idx)
      const qHidden = document.getElementById("faq_q_hidden_" + idx)
      const aField  = document.getElementById("faq_a_field_" + idx)
      const aHidden = document.getElementById("faq_a_hidden_" + idx)
      if (qField && qHidden) qHidden.value = qField.value || ""
      if (aField && aHidden) aHidden.value = aField.value || ""
    })
  }

  _setReviewSelection(checked) {
    this.element.querySelectorAll(".faq-preview-checkbox").forEach(checkbox => {
      checkbox.checked = checked
    })
    this._updateSelectedCount()
  }

  _updateSelectedCount() {
    const checkboxes = Array.from(this.element.querySelectorAll(".faq-preview-checkbox"))
    const selected = checkboxes.filter(checkbox => checkbox.checked).length
    const count = document.getElementById("faq_selected_count")
    if (count) count.textContent = `${selected} selected`
  }

  // ── Cancel / close ───────────────────────────────────────────────────────

  close(e) {
    e.preventDefault()
    const closeBtn = document.getElementById("faq-import-modal-close")
    if (closeBtn) closeBtn.click()

    const frame = document.getElementById("faq_import_panel")
    if (frame && this.hasResetUrlValue) frame.src = this.resetUrlValue
  }
}
