class VersionsController < ApplicationController

  # NOT DONE
  def index
    @versions = Version.all.includes(:test_instances, :test_cases)
    @row_classes = {}
    @versions.each do |version|
      @row_classes[version] = case version.status
                              when 0 then 'row-success'
                              when 1 then 'row-warning'
                              when 2 then 'row-danger'
                              else
                                'row-info'
                              end
    end
  end
end
