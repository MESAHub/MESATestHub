# Provider-agnostic SMTP wiring. Defaults to Resend
# (smtp.resend.com) because that's what production runs, but every
# value is overridable via env vars so a future provider swap is a
# config change rather than a code change.
#
# Required env vars in production:
#   SMTP_PASSWORD  — for Resend, the API key value
#                    (or set RESEND_API_KEY and we'll pick it up)
#
# Optional (defaults match Resend's STARTTLS endpoint):
#   SMTP_HOST  — default smtp.resend.com
#   SMTP_PORT  — default 587 (STARTTLS); 465 / 2465 for implicit TLS
#   SMTP_USER  — default 'resend'
#
# TLS strategy is auto-picked by port: 465 / 2465 use implicit TLS
# (TLS handshake on connect), every other port uses STARTTLS (plain
# socket then upgrade). Default is 587 because some cloud providers
# (Railway included) only allow outbound STARTTLS, not implicit TLS.
class ApplicationMailer < ActionMailer::Base
  # From-address domain (testhub.mesastar.org) is the one we verify
  # with the email provider. Any future mailer overrides this via
  # its own `default from:`.
  default from: 'digest@testhub.mesastar.org'
  layout 'mailer'
end

smtp_port = ENV.fetch('SMTP_PORT', '587').to_i
tls_options =
  if [465, 2465].include?(smtp_port)
    { tls: true }
  else
    { enable_starttls_auto: true }
  end

ApplicationMailer.smtp_settings = {
  address:        ENV.fetch('SMTP_HOST', 'smtp.resend.com'),
  port:           smtp_port,
  user_name:      ENV.fetch('SMTP_USER', 'resend'),
  password:       ENV['SMTP_PASSWORD'] || ENV['RESEND_API_KEY'],
  domain:         'testhub.mesastar.org',
  authentication: :plain
}.merge(tls_options)
ApplicationMailer.delivery_method = :smtp
