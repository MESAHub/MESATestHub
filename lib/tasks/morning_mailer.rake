namespace :morning_mailer do
  desc 'Send the daily MESA Test Hub digest to mesa-developers ' \
       '(only fires when local clock reads 8 AM Eastern; set FORCE=1 ' \
       'to send regardless).'
  task daily: :environment do
    eastern_hour = Time.now.in_time_zone('America/New_York').hour
    force = ENV['FORCE'] == '1'

    if eastern_hour != 8 && !force
      puts "Skipping: #{Time.now.in_time_zone('America/New_York').strftime('%H:%M %Z')} " \
           "is not 8 AM Eastern. Set FORCE=1 to send anyway."
      next
    end

    puts 'Sending out morning digest...'
    MorningMailer.daily.deliver_now
    puts 'done.'
  end
end
