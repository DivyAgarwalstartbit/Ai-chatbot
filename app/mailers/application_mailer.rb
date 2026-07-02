class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SMTP_FROM_EMAIL", ENV.fetch("SMTP_USERNAME", "noreply@example.com"))
  layout "mailer"
end
