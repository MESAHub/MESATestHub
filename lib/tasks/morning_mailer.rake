namespace :morning_mailer do
  desc 'Send the daily MESA Test Hub digest to mesa-developers.'
  task daily: :environment do
    puts 'Sending out morning digest...'
    MorningMailer.daily.deliver_now
    puts 'done.'
  end
end
