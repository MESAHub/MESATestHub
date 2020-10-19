# Preview all emails at http://localhost:3000/rails/mailers/morning_mailer
class MorningMailerPreview < ActionMailer::Preview
  def morning_email_3
    MorningMailer.morning_email_3
  end
end