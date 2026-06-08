import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["answer", "toggle"]

  toggle(event) {
    event.preventDefault()
    const expanded = this.answerTarget.classList.toggle("is-expanded")
    this.toggleTarget.textContent = expanded ? "Show less" : "Show more"
    this.toggleTarget.setAttribute("aria-expanded", expanded ? "true" : "false")
  }
}
