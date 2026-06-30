class Message < ApplicationRecord
  belongs_to :conversation

  ROLES = %w[user customer assistant system agent].freeze

  validates :role, inclusion: { in: ROLES }
  validates :content, presence: true
end
