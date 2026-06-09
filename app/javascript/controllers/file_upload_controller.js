import { Controller } from "@hotwired/stimulus"

// Handles the file-picker drop zone for FAQ document uploads.
// Targets:
//   input    — hidden <input type="file">
//   dropZone — clickable drop zone box
//   badge    — filename display element (inside file info box)
//   submit   — upload button (enabled once a file is chosen)
export default class extends Controller {
  static targets = ["input", "dropZone", "badge", "submit"]

  connect() {
    this.dropZoneTarget.addEventListener("dragover",  this.#onDragOver.bind(this))
    this.dropZoneTarget.addEventListener("dragleave", this.#onDragLeave.bind(this))
    this.dropZoneTarget.addEventListener("drop",      this.#onDrop.bind(this))
  }

  open() {
    this.inputTarget.click()
  }

  fileChosen() {
    this.#setFile(this.inputTarget.files[0])
  }

  clear() {
    this.inputTarget.value = ""
    if (this.hasBadgeTarget) this.badgeTarget.textContent = ""
    if (this.hasSubmitTarget) this.submitTarget.setAttribute("disabled", "")
    this.#setFileInfoVisible(false)
  }

  #onDragOver(e) {
    e.preventDefault()
    this.dropZoneTarget.setAttribute("background", "base")
  }

  #onDragLeave() {
    this.dropZoneTarget.setAttribute("background", "subdued")
  }

  #onDrop(e) {
    e.preventDefault()
    this.dropZoneTarget.setAttribute("background", "subdued")
    const file = e.dataTransfer?.files[0]
    if (!file) return
    const dt = new DataTransfer()
    dt.items.add(file)
    this.inputTarget.files = dt.files
    this.#setFile(file)
  }

  #setFile(file) {
    if (!file) return
    if (this.hasBadgeTarget) this.badgeTarget.textContent = file.name
    if (this.hasSubmitTarget) this.submitTarget.removeAttribute("disabled")
    this.#setFileInfoVisible(true)
  }

  #setFileInfoVisible(visible) {
    const infoBox = document.getElementById("faq_upload_file_info")
    if (infoBox) infoBox.style.display = visible ? "" : "none"
  }
}
