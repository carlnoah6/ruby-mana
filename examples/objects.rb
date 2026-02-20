# frozen_string_literal: true

# Example: LLM reads and writes object attributes
require "mana"

class Email
  attr_accessor :subject, :body, :sender, :category, :priority

  def initialize(subject:, body:, sender:)
    @subject = subject
    @body = body
    @sender = sender
  end

  def to_s
    "Email(#{subject}, category=#{category}, priority=#{priority})"
  end
end

email = Email.new(
  subject: "URGENT: Production server down",
  body: "Database connection pool exhausted, all requests timing out",
  sender: "ops@company.com"
)

~"read <email> subject and body, set category to urgent/bug/feature/spam and priority to high/medium/low"

puts email
