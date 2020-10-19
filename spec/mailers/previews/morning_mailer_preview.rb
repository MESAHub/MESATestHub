# Preview all emails at http://localhost:3000/rails/mailers/morning_mailer
# require 'send-grid-ruby'
class MorningMailerPreview < ActionMailer::Preview
  include SendGrid
  def morning_email_3
    MorningMailer.morning_email_3
  end
end
