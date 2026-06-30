import { Controller } from "@hotwired/stimulus"

// Handles the Sync From Shopify button UX within a policy accordion body.
//
// The sync form has data-turbo="false" so Turbo never touches it — this
// prevents Turbo's form-submission machinery from setting loading/disabled
// on unrelated buttons (like Edit Policy) in the same DOM scope.
//
// Instead, this controller submits the form manually via fetch and renders
// the Turbo Stream response itself.
export default class extends Controller {
  connect() {
    this._observer = new MutationObserver(() => this._onBannerChange())
    const banners = this.element.querySelectorAll('[id$="_sync_banner"]')
    banners.forEach(el => this._observer.observe(el, { childList: true, subtree: true }))
  }

  disconnect() {
    this._observer?.disconnect()
  }

  // Called by: data-action="click->policy-sync#startSync"
  startSync(e) {
    e.preventDefault()

    const policyType = e.params?.policyType ||
      e.target.closest('[data-policy-sync-policy-type-param]')
               ?.dataset.policySyncPolicyTypeParam

    if (!policyType) return

    const btn = document.getElementById(`${policyType}_sync_btn`)
    if (btn) {
      btn.setAttribute('loading', '')
      btn.setAttribute('disabled', '')
    }

    this._activePolicyType = policyType

    // Submit the form manually so Turbo never touches other buttons.
    const form = document.getElementById(`${policyType}_sync_form`)
    if (!form) return

    const url    = form.action
    const csrfEl = document.querySelector('meta[name="csrf-token"]')
    const body   = new URLSearchParams(new FormData(form))

    fetch(url, {
      method:  'POST',
      headers: {
        'X-CSRF-Token': csrfEl?.content ?? '',
        'Accept':       'text/vnd.turbo-stream.html',
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body
    })
    .then(res => res.text())
    .then(async html => {
      if (window.Turbo && typeof window.Turbo.renderStreamMessage === 'function') {
        await window.Turbo.renderStreamMessage(html)
      }
      this.stopLoading(policyType)
    })
    .catch(() => {
      this.stopLoading(policyType)
    })
  }

  // Called by inline scripts in sync.turbo_stream.erb, sync_error.turbo_stream.erb,
  // and confirm.turbo_stream.erb
  stopLoading(policyType) {
    const type = policyType || this._activePolicyType
    if (!type) return
    const btn = document.getElementById(`${type}_sync_btn`)
    if (btn) {
      btn.removeAttribute('loading')
      btn.removeAttribute('disabled')
    }
  }

  _onBannerChange() {
    if (!this._activePolicyType) return
    const banner = document.getElementById(`${this._activePolicyType}_sync_banner`)
    if (banner && banner.children.length > 0) {
      this.stopLoading(this._activePolicyType)
    }
  }
}
