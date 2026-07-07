module ApplicationHelper
  # ── Policy configuration ────────────────────────────────────────────────────

  # A policy is "configured" if it has any content from any source.
  def policy_configured?(policy)
    policy.content.present? ||
      policy.shopify_content.present? ||
      policy.file.attached?
  end

  # Returns an array of badge hashes for all active sources on this policy.
  # source_type is a space-separated string of tokens: "manual_entry shopify_sync"
  def policy_source_badges(policy)
    sources = policy.source_type.to_s.split
    badges  = []

    if policy.content.present?
      badges << { label: "Manual Entry", tone: "info", icon: "edit" }
    end

    if policy.file.attached?
      label = policy.content.present? ? "Uploaded Document" : "Uploaded Document"
      badges << { label: label, tone: "success", icon: "file" }
    end

    if policy.shopify_content.present?
      badges << { label: "Shopify Sync", tone: "attention", icon: "refresh" }
    end

    badges
  end

  def policy_empty_message(policy_type)
    "No #{policy_type.to_s.humanize.downcase} has been provided yet."
  end

  def policy_updated_text(policy)
    return "" unless policy_configured?(policy) && policy.updated_at.present?

    if policy.updated_at > 7.days.ago
      "Updated #{time_ago_in_words(policy.updated_at)} ago"
    else
      "Updated #{policy.updated_at.to_date.to_fs(:long)}"
    end
  end

  def policy_synced_text(policy)
    return nil unless policy.respond_to?(:synced_at) && policy.synced_at.present?

    if policy.synced_at > 7.days.ago
      "Last synced #{time_ago_in_words(policy.synced_at)} ago"
    else
      "Last synced #{policy.synced_at.strftime("%-d %B %Y, %-I:%M %p")}"
    end
  end

  # ── FAQ helpers ─────────────────────────────────────────────────────────────

  def faq_answer_needs_toggle?(faq)
    faq.content.to_s.length > 220
  end
end
