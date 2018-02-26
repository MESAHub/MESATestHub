module ApplicationHelper
  def format_time(time)
    time_zone = 'utc'
    time_zone = current_user.time_zone if current_user
    I18n.l time.to_time.in_time_zone(time_zone), format: short
  end
end
