# Provider-agnostic SMTP wiring. Defaults to Resend (smtp.resend.com)
# because that's what production runs, but every value is overridable
# via env vars so a future provider swap is a config change rather
# than a code change.
#
# Required env vars in production:
#   SMTP_PASSWORD  — for Resend, the API key value
#                    (or set RESEND_API_KEY and we'll pick it up)
#
# Optional (defaults match Resend's SMTP endpoint):
#   SMTP_HOST  — default smtp.resend.com
#   SMTP_PORT  — default 465 (implicit TLS)
#   SMTP_USER  — default 'resend'
class ApplicationMailer < ActionMailer::Base
  # From-address domain (testhub.mesastar.org) is the one we verify
  # with the email provider. Any future mailer overrides this via
  # its own `default from:`.
  default from: 'digest@testhub.mesastar.org'
  layout 'mailer'
end

ApplicationMailer.smtp_settings = {
  address:        ENV.fetch('SMTP_HOST', 'smtp.resend.com'),
  port:           ENV.fetch('SMTP_PORT', '465').to_i,
  user_name:      ENV.fetch('SMTP_USER', 'resend'),
  password:       ENV['SMTP_PASSWORD'] || ENV['RESEND_API_KEY'],
  domain:         'testhub.mesastar.org',
  authentication: :plain,
  tls:            true
}
ApplicationMailer.delivery_method = :smtp
