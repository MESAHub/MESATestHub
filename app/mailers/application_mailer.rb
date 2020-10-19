class ApplicationMailer < ActionMailer::Base
  default from: 'mesa-developers@lists.mesastar.org'
  layout 'mailer'
end

ApplicationMailer::Base.smtp_settings = {
  :port           => ENV['MAILGUN_SMTP_PORT'],
  :address        => ENV['MAILGUN_SMTP_SERVER'],
  :user_name      => ENV['MAILGUN_SMTP_LOGIN'],
  :password       => ENV['MAILGUN_SMTP_PASSWORD'],
  :domain         => 'yourapp.heroku.com',
  :authentication => :plain
}
ApplicationMailer::Base.delivery_method = :smtp