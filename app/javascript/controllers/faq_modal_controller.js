import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "modal",
    "form",
    "method",
    "questionField",
    "answerField",
    "titleHidden",
    "contentHidden",
    "error",
    "submitButton",
  ]

  static values = {
    createUrl: String,
  }

  openNew(event) {
    event.preventDefault()
    this._prepareForm({
      heading: "Add FAQ",
      action: this.createUrlValue,
      method: "",
      question: "",
      answer: "",
      submitText: "Save FAQ",
    })
    this._showModal()
  }

  openEdit(event) {
    event.preventDefault()
    const trigger = event.currentTarget

    this._prepareForm({
      heading: "Edit FAQ",
      action: trigger.dataset.updatePath,
      method: "patch",
      question: trigger.dataset.faqTitle || "",
      answer: trigger.dataset.faqContent || "",
      submitText: "Update FAQ",
    })
    this._showModal()
  }

  submit(event) {
    event.preventDefault()
    this._syncFields()

    if (this.hasErrorTarget) this.errorTarget.innerHTML = ""
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.loading = true
    if (this.hasFormTarget) this.formTarget.requestSubmit()
  }

  submitEnd() {
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.loading = false
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.loading = false
  }

  _prepareForm({ heading, action, method, question, answer, submitText }) {
    if (this.hasModalTarget) this.modalTarget.setAttribute("heading", heading)
    if (this.hasFormTarget) this.formTarget.action = action

    if (this.hasMethodTarget) {
      if (method) {
        this.methodTarget.disabled = false
        this.methodTarget.value = method
      } else {
        this.methodTarget.value = ""
        this.methodTarget.disabled = true
      }
    }

    this._setFieldValue(this.questionFieldTarget, question)
    this._setFieldValue(this.answerFieldTarget, answer)
    if (this.hasTitleHiddenTarget) this.titleHiddenTarget.value = question
    if (this.hasContentHiddenTarget) this.contentHiddenTarget.value = answer
    if (this.hasErrorTarget) this.errorTarget.innerHTML = ""
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.textContent = submitText
      this.submitButtonTarget.loading = false
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

  _showModal() {
    if (this.hasModalTarget && typeof this.modalTarget.showOverlay === "function") {
      this.modalTarget.showOverlay()
    }

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
