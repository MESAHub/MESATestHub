class MorningMailerJob < ApplicationJob
  queue_as :default

  # Daily mesa-developers digest. Fired twice in UTC (12:00 + 13:00)
  # from config/recurring.yml so it lands at 08:00 US Eastern across
  # the DST boundary; the off-hour fire short-circuits here. Same
  # guard the old morning_mailer:daily rake task carried. Pass
  # force: true to send regardless of the local clock.
  #
  # Uses deliver_later so a transient Resend failure becomes a queued
  # mailer retry rather than a missed digest day.
  def perform(force: false)
    eastern_hour = Time.now.in_time_zone('America/New_York').hour
    return if eastern_hour != 8 && !force

    MorningMailer.daily.deliver_later
  end
end
