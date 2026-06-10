class Message < ApplicationRecord
  belongs_to :conversation

  ROLES = %w[customer assistant system].freeze

  validates :role, inclusion: { in: ROLES }
  validates :content, presence: true
end
