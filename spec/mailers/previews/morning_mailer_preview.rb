# Preview the daily digest at
# http://localhost:3000/rails/mailers/morning_mailer/daily
class MorningMailerPreview < ActionMailer::Preview
  def daily
    MorningMailer.daily
  end
end
