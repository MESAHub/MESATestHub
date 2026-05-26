# Email delivery via Resend's HTTPS API.
#
# Originally configured for SMTP, but Railway blocks outbound SMTP
# entirely (both 465 and 587 time out at TCP-connect).  Resend's
# REST API over HTTPS bypasses the block.
#
# The `resend` gem registers a `:resend` ActionMailer delivery
# method that takes a Mail::Message and POSTs it to
# https://api.resend.com/emails.  Quirk in resend 1.3.0: the gem
# checks the *global* `Resend.api_key` on every delivery, ignoring
# the per-mailer `resend_settings[:api_key]` that Rails passes in.
# So we set the global directly — see
# `gems/resend-1.3.0/lib/resend/mailer.rb:25`.
#
# Required env var in production:
#   RESEND_API_KEY  — API key from the Resend dashboard
#
# The test environment keeps its `:test` delivery method (set in
# config/environments/test.rb), so specs don't hit the network.
require "resend"

class ApplicationMailer < ActionMailer::Base
  # From-address domain (testhub.mesastar.org) is the one verified
  # in Resend.  Any future mailer overrides this via its own
  # `default from:`.
  default from: 'digest@testhub.mesastar.org'
  layout 'mailer'
end

if Rails.env.production?
  Resend.api_key = ENV['RESEND_API_KEY']
  ApplicationMailer.delivery_method = :resend
end
