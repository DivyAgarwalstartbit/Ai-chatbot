import { Controller } from "@hotwired/stimulus"

// Unified modal controller handling two patterns:
//
//   1. FAQ s-modal (type: "faq")
//      Targets: modal, form, method, questionField, answerField,
//               titleHidden, contentHidden, error, submitButton
//      Values:  createUrl [String]
//
//   2. Policy overlay modal (type: "policy")
//      Targets: modal, backdrop, textarea, hidden
//      The overlay is a plain CSS div toggled via display:flex/none.
//
// Set data-modal-type-value="faq" or "policy" on the controller element.

export default class extends Controller {
  static targets = [
    // shared
    "modal",
    // faq modal
    "form", "method", "questionField", "answerField",
    "titleHidden", "contentHidden", "error", "submitButton",
    // policy modal
    "backdrop", "textarea", "hidden",
  ]

  static values = {
    type:      { type: String, default: "policy" },
    createUrl: String,
  }

  // ── Policy modal ────────────────────────────────────────────────────────────

  open(e) {
    e.preventDefault()
    if (this.hasModalTarget) {
      this.modalTarget.style.display = "flex"
      document.body.style.overflow   = "hidden"
      requestAnimationFrame(() => {
        if (this.hasTextareaTarget) this.textareaTarget.focus()
      })
    }
  }

  close(e) {
    if (e) e.preventDefault()
    if (this.typeValue === "faq") {
      if (this.hasSubmitButtonTarget) this.submitButtonTarget.loading = false
    } else {
      if (this.hasModalTarget) {
        this.modalTarget.style.display = "none"
        document.body.style.overflow   = ""
      }
      // Discard unsaved policy changes — hide the save bar
      if (typeof hideSaveBar === "function") hideSaveBar()
    }
  }

  backdropClick(e) {
    if (e.target === e.currentTarget) this.close(e)
  }

  // Sync s-text-area → hidden input, then submit the policy form
  submit(e) {
    e.preventDefault()
    if (this.typeValue === "faq") {
      this._faqSubmit()
    } else {
      if (this.hasTextareaTarget && this.hasHiddenTarget) {
        this.hiddenTarget.value = this.textareaTarget.value
      }
      const form = this.element.querySelector("form[data-policy-form]")
      if (form) form.requestSubmit()
    }
  }

  // ── FAQ modal ───────────────────────────────────────────────────────────────

  openNew(event) {
    // The triggering button already has commandFor/command="--show", so the modal
    // opens natively. We only need to prepare the form fields.
    this._prepareForm({
      heading:    "Add FAQ",
      action:     this.createUrlValue,
      method:     "",
      question:   "",
      answer:     "",
      submitText: "Save FAQ",
    })
  }

  openEdit(event) {
    event.preventDefault()
    const trigger = event.currentTarget
    this._prepareForm({
      heading:    "Edit FAQ",
      action:     trigger.dataset.updatePath,
      method:     "patch",
      question:   trigger.dataset.faqTitle   || "",
      answer:     trigger.dataset.faqContent || "",
      submitText: "Update FAQ",
    })
    // Edit button has no commandFor, so open the modal programmatically.
    this._showFaqModal()
  }

  submitEnd(event) {
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.loading = false
    if (event.detail && event.detail.success) {
      const closeBtn = document.getElementById("faq-form-modal-close")
      if (closeBtn) closeBtn.click()
    }
  }

  policySubmitEnd(event) {
    if (event.detail && event.detail.success) {
      if (this.hasModalTarget) {
        this.modalTarget.style.display = "none"
        document.body.style.overflow   = ""
      }
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  _faqSubmit() {
    this._syncFields()
    if (this.hasErrorTarget)        this.errorTarget.innerHTML = ""
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.loading = true
    if (this.hasFormTarget)         this.formTarget.requestSubmit()
  }

  _prepareForm({ heading, action, method, question, answer, submitText }) {
    if (this.hasModalTarget) this.modalTarget.setAttribute("heading", heading)
    if (this.hasFormTarget)  this.formTarget.action = action

    if (this.hasMethodTarget) {
      if (method) {
        this.methodTarget.disabled = false
        this.methodTarget.value    = method
      } else {
        this.methodTarget.value    = ""
        this.methodTarget.disabled = true
      }
    }

    this._setFieldValue(this.questionFieldTarget, question)
    this._setFieldValue(this.answerFieldTarget,   answer)
    if (this.hasTitleHiddenTarget)   this.titleHiddenTarget.value   = question
    if (this.hasContentHiddenTarget) this.contentHiddenTarget.value = answer
    if (this.hasErrorTarget)         this.errorTarget.innerHTML     = ""
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.textContent = submitText
      this.submitButtonTarget.loading     = false
    }
  }

  _syncFields() {
    if (this.hasTitleHiddenTarget && this.hasQuestionFieldTarget) {
      this.titleHiddenTarget.value = this.questionFieldTarget.value || ""
    }
    if (this.hasContentHiddenTarget && this.hasAnswerFieldTarget) {
      this.contentHiddenTarget.value = this.answerFieldTarget.value || ""
    }
  }

  _showFaqModal() {
    const showBtn = document.getElementById("faq-form-modal-show")
    if (showBtn) showBtn.click()
    requestAnimationFrame(() => {
      if (this.hasQuestionFieldTarget) this.questionFieldTarget.focus()
    })
  }

  _setFieldValue(field, value) {
    if (!field) return
    field.value = value
    field.setAttribute("value", value)
  }
}
