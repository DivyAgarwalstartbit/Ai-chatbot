class Ticket < ApplicationRecord
  belongs_to :shop
  belongs_to :customer, optional: true
  belongs_to :conversation, optional: true

  SOURCES = %w[customer_requested_human ai_escalation merchant_created].freeze
  STATUSES = %w[open in_progress resolved closed].freeze
  PRIORITIES = %w[low normal high urgent].freeze

  validates :subject, presence: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }, allow_nil: true
  validates :priority, inclusion: { in: PRIORITIES }, allow_nil: true
end
