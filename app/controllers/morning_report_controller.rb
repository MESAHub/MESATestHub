# Web preview of the daily mesa-developers digest. Renders the same
# data + same template that MorningMailer emails out, so the
# in-browser view exactly tracks what subscribers see in their inbox.
#
# Results are cached for 24 hours per date (see MorningReport.for); pass
# ?refresh=1 to bust the cache and rebuild on the next request.
class MorningReportController < ApplicationController
  layout "modern"

  def show
    @date = parse_date_param || Date.current
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
