# Web preview of the daily mesa-developers digest. Renders the same
# data + same template that MorningMailer emails out, so the
# in-browser view exactly tracks what subscribers see in their inbox.
#
# A sent digest's report is cached for 24 hours per date (see
# MorningReport.for); pass ?refresh=1 to rebuild it. Before 8 AM Eastern,
# today's preview is built live with the window ending now.
class MorningReportController < ApplicationController
  layout "modern"

  def show
    @date = parse_date_param || MorningReport.current_date
    @report = MorningReport.for(date: @date, force: params[:refresh].present?)
  end

  private

  def parse_date_param
    return nil if params[:date].blank?

    Date.parse(params[:date])
  rescue Date::Error
    nil
  end
end
