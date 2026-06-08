import { Controller } from "@hotwired/stimulus"

// Opens/closes a modal overlay for editing policies.
//
// Each policy section wrapper gets data-controller="policy-modal".
// The modal div inside it gets data-policy-modal-target="modal backdrop".
// The textarea gets data-policy-modal-target="textarea".
// The hidden input gets data-policy-modal-target="hidden".
//
// The "Edit Policy" button fires: data-action="click->policy-modal#open"
// The "Save" button fires:        data-action="click->policy-modal#submit"
// The "Cancel" button fires:      data-action="click->policy-modal#close"
// The backdrop fires:             data-action="click->policy-modal#backdropClick"
export default class extends Controller {
  static targets = ["modal", "backdrop", "textarea", "hidden"]

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
    if (this.hasModalTarget) {
      this.modalTarget.style.display = "none"
      document.body.style.overflow   = ""
    }
  }

  // Close only when clicking the dark backdrop, not the white dialog card
  backdropClick(e) {
    if (e.target === e.currentTarget) this.close(e)
  }

  // Sync s-text-area → hidden input, then submit the form
  submit(e) {
    e.preventDefault()
    if (this.hasTextareaTarget && this.hasHiddenTarget) {
      this.hiddenTarget.value = this.textareaTarget.value
    }
    const form = this.element.querySelector("form[data-policy-form]")
    if (form) form.requestSubmit()
  }
}
