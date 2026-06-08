import { Controller } from "@hotwired/stimulus"

// Controls the FAQ Suggestions modal.
//
// Responsibilities:
//   - Open the modal and reset the panel to the prompt screen
//   - Trigger the suggest form (shows loading, submits via Turbo)
//   - Sync s-text-field / s-text-area values to hidden inputs before import submit
//   - Handle "Regenerate" (re-submit the suggest form from the preview screen)
//   - Restore button state after error Turbo Streams
export default class extends Controller {
  static values = {
    suggestUrl: String,
    importUrl:  String,
  }

  // ── Open modal ───────────────────────────────────────────────────────────

  openModal(e) {
    // The s-modal is opened by commandFor="faq-suggestions-modal" already;
    // this action resets the panel to the initial prompt screen each time.
    const panel = document.getElementById("faq_suggestion_panel")
    if (panel) {
      // Reset to the initial state turbo frame src — causes the frame to re-render
      // the _suggestion_panel partial (server-side, no network request needed here
      // because the panel content is already in DOM from the page load).
      // We just clear any leftover preview and error state.
      this._clearError()
    }
  }

  // ── Generate suggestions ─────────────────────────────────────────────────

  generate(e) {
    if (e) e.preventDefault()

    const btn = document.getElementById("faq_suggest_btn")
    if (btn) { btn.setAttribute("loading", ""); btn.setAttribute("disabled", "") }

    const loading = document.getElementById("faq_suggestion_loading")
    if (loading) loading.style.display = ""

    this._clearError()

    const form = document.getElementById("faq_suggest_form")
    if (form) form.requestSubmit()
  }

  // ── Regenerate (from preview screen) ────────────────────────────────────

  regenerate(e) {
    if (e) e.preventDefault()

    // Reset panel back to the initial prompt view then trigger generation.
    const panelFrame = document.getElementById("faq_suggestion_panel")
    if (panelFrame && this.hasSuggestUrlValue) {
      panelFrame.src = ""  // clear cached frame
    }

    // Directly POST to suggest endpoint via fetch with turbo-stream accept
    const btn = e?.currentTarget
    if (btn) { btn.setAttribute("loading", ""); btn.setAttribute("disabled", "") }

    fetch(this.suggestUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        "Accept":       "text/vnd.turbo-stream.html",
        "Content-Type": "application/x-www-form-urlencoded"
      }
    })
    .then(res => res.text())
    .then(html => {
      if (window.Turbo && typeof window.Turbo.renderStreamMessage === "function") {
        window.Turbo.renderStreamMessage(html)
      }
    })
    .catch(() => {
      if (btn) { btn.removeAttribute("loading"); btn.removeAttribute("disabled") }
    })
  }

  // ── Import selected suggestions ──────────────────────────────────────────

  submitImport(e) {
    if (e) e.preventDefault()

    // Sync Polaris s-text-field / s-text-area values → hidden inputs
    this.element.querySelectorAll(".faq-preview-row").forEach(row => {
      const idx     = row.dataset.idx
      const qField  = document.getElementById("faq_q_field_"  + idx)
      const qHidden = document.getElementById("faq_q_hidden_" + idx)
      const aField  = document.getElementById("faq_a_field_"  + idx)
      const aHidden = document.getElementById("faq_a_hidden_" + idx)
      if (qField  && qHidden) qHidden.value = qField.value  || ""
      if (aField  && aHidden) aHidden.value = aField.value  || ""
    })

    const importBtn = document.getElementById("suggest_import_btn")
    if (importBtn) { importBtn.setAttribute("loading", ""); importBtn.setAttribute("disabled", "") }

    const form = document.getElementById("faq_suggestions_import_form")
    if (form) form.requestSubmit()
    else this.element.querySelector("form")?.requestSubmit()
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

  // ── Close ────────────────────────────────────────────────────────────────

  close(e) {
    if (e) e.preventDefault()
    const modal = document.getElementById("faq-suggestions-modal")
    if (modal && typeof modal.hideOverlay === "function") modal.hideOverlay()
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  _clearError() {
    const err = document.getElementById("faq_suggestion_error")
    if (err) err.innerHTML = ""
    const importErr = document.getElementById("faq_suggestion_import_error")
    if (importErr) importErr.innerHTML = ""
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
    const count = document.getElementById("suggest_selected_count")
    if (count) count.textContent = `${selected} selected`
  }
}
