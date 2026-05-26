# Email delivery via Resend's HTTPS API.
#
# Originally configured for SMTP, but Railway blocks outbound SMTP
# entirely (both implicit-TLS on 465 and STARTTLS on 587 time out at
# the TCP-connect stage). Switching to Resend's REST API over HTTPS
# bypasses the block — Railway doesn't restrict outbound HTTPS.
#
# The `resend` gem registers a `:resend` ActionMailer delivery
# method that takes a Mail::Message and POSTs it to
# https://api.resend.com/emails. Same `Mailer#action.deliver_now`
# call site — only the wire format changes.
#
# Required env var in production:
#   RESEND_API_KEY  — API key from the Resend dashboard
#
# The test environment keeps its `:test` delivery method (set in
# config/environments/test.rb), so specs don't hit the network.
class ApplicationMailer < ActionMailer::Base
  # From-address domain (testhub.mesastar.org) is the one verified
  # in Resend. Any future mailer overrides this via its own
  # `default from:`.
  default from: 'digest@testhub.mesastar.org'
  layout 'mailer'
end

if Rails.env.production?
  ApplicationMailer.delivery_method = :resend
  ApplicationMailer.resend_settings = { api_key: ENV['RESEND_API_KEY'] }
end
