import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages", "input", "submit"]
  static values  = { conversationId: Number, replyUrl: String }

  connect() {
    this._scrollBottom()
    if (!this.conversationIdValue) return

    // ActionCable is loaded as a UMD global via /action_cable.js in the layout
    if (typeof ActionCable === "undefined") {
      console.warn("[TicketChat] ActionCable not loaded yet")
      return
    }

    this._consumer = ActionCable.createConsumer()
    this._subscription = this._consumer.subscriptions.create(
      { channel: "ConversationChannel", conversation_id: this.conversationIdValue },
      { received: (data) => this._appendBubble(data) }
    )
  }

  disconnect() {
    this._subscription?.unsubscribe()
    this._consumer?.disconnect()
  }

  submit(event) {
    event.preventDefault()
    const content = this.inputTarget.value.trim()
    if (!content) return

    this.submitTarget.disabled = true

    fetch(this.replyUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify({ content })
    })
      .then(r => r.json())
      .then(() => { this.inputTarget.value = "" })
      .catch(console.error)
      .finally(() => { this.submitTarget.disabled = false })
  }

  inputKeydown(event) {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      this.submit(event)
    }
  }

  _appendBubble(data) {
    const wrap = document.createElement("div")
    wrap.className = `tl-bubble-wrap ${data.role}`

    const senderLabel = data.role === "agent"
      ? '<span class="tl-sender agent-label">Support Agent</span>'
      : ""

    wrap.innerHTML = `
      ${senderLabel}
      <div class="tl-bubble ${data.role}">${this._esc(data.content)}</div>
      <span class="tl-time">${this._esc(data.time)}</span>
    `

    this.messagesTarget.appendChild(wrap)
    this._scrollBottom()
  }

  _scrollBottom() {
    const el = this.messagesTarget
    if (el) el.scrollTop = el.scrollHeight
  }

  _esc(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
  }
}
