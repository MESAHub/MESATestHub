# Daily digest email for mesa-developers. The actual data-shaping lives
# in MorningReport — this class is the deliverer + the URL host wiring.
#
# Old morning_email / morning_email_2 / morning_email_3 methods were
# welded to the dropped `Version` model + `mesa_version` column; they
# are gone. Their feature surface (commit-level status roll-up,
# release-blocker count, runtime/RAM anomaly detection) is reconstituted
# in MorningReport on top of the commits-based data model.
class MorningMailer < ApplicationMailer
  layout 'morning_mailer'

  # Hardcoded — `testhub.mesastar.org` is the long-term canonical
  # URL regardless of which provider hosts the app. If we ever move
  # off Railway, the DNS record moves with the URL and these links
  # keep resolving. Update here only if the canonical hostname
  # itself changes.
  default_url_options[:host] =
    Rails.env.production? ? 'testhub.mesastar.org' : 'localhost:3000'
  default_url_options[:protocol] = Rails.env.production? ? 'https' : 'http'

  # mesa-developers list + the Slack inbound-mail address that pipes the
  # digest into the #testhub channel.
  RECIPIENTS = [
    'mesa-developers@lists.mesastar.org',
    'p7r3d3c7y5u1u9e8@mesadevelopers.slack.com'
  ].freeze

  def daily(date: Date.current, recipients: RECIPIENTS)
    @report = MorningReport.for(date: date)
    @date = date

    mail(to: Array(recipients).join(', '),
         subject: "MESA Test Hub digest — #{date.strftime('%Y-%m-%d')}")
  end
end
