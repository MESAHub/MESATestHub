class MorningMailer < ApplicationMailer
  include SendGrid

  def initialize
    @client = SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY']).client
  end

  def default_url_options
    if Rails.env.production?
      { host: 'https://testhub.mesastar.org' }
    elsif Rails.env.development?
      { host: 'http://localhost:3000' }
    else
      { host: 'http://localhost:3000' }
    end
  end

  def morning_email
    # first gather data from database; bail if there are no failure in the last
    # 24 hours
    start_date = 1.day.ago
    @versions_tested = Version.tested_between(start_date, DateTime.now)
    @versions_tested.sort_by! { |version| -version.number }
    @version_data = @versions_tested.map do |version|
      res = {
        version: version,
        status: case version.status
        when 3 then :mixed
        when 2 then :checksums
        when 1 then :failing
        when 0 then :passing
        else
          :other          
        end,
        link: version_url(version.number),
        case_count: version.test_case_versions.count,
        computer_counts: { total: version.computers_count },
        failing_cases: version.test_case_versions.where(status: 1).to_a,
        checksum_cases: version.test_case_versions.where(status: 2).to_a,
        mixed_cases: version.test_case_versions.where(status: 3).to_a,
        case_links: {},
        pass_counts: {},
        fail_counts: {},
        checksum_counts: {}
      }
      version.test_case_versions.each do |tcv|
        res[:computer_counts][tcv] = tcv.computer_count
        res[:pass_counts][tcv] = tcv.test_instances.where(passed: true).count
        res[:fail_counts][tcv] = tcv.test_instances.where(passed: false).count
        if tcv.status >= 2
          res[:checksum_counts][tcv] = tcv.unique_checksum_count
        end
        res[:case_links][tcv] = test_case_version_url(
          version.number, tcv.test_case.name
        )
      end
      res
    end
    @make_green = "style='color: rgb(0, 153, 51)'"
    @make_yellow = "style= 'color: rgb(255, 153, 0)'"
    @make_blue = "style= 'color: rgb(78, 114, 219)'"
    @make_red = "style='color: rgb(204, 0, 0)'"

    # @mixed_versions = []
    # @mixed_checksums_versions = []
    # @failing_versions = []
    # @passing_versions = []
    # @other_versions = []
    # @version_links = {}
    # @computer_counts = {}
    # @case_counts = {}
    # @failing_cases = {}
    # @mixed_cases = {}
    # @checksum_cases = {}
    # @pass_counts = {}
    # @fail_counts = {}
    # @checksum_counts = {}
    # @case_links = {}

    # @versions_tested.each do |version|
    #   case version.status
    #   when 3 then @mixed_versions.append(version)
    #   when 2 then @mixed_checksums_versions.append(version)
    #   when 1 then @failing_versions.append(version)
    #   when 0 then @passing_versions.append(version)
    #   else
    #     @other_versions.append(version)
    #   end
    #   @failing_cases[version] = version.test_case_versions.where(status: 1).to_a
    #   @checksum_cases[version] = version.test_case_versions.where(status: 2).to_a
    #   @mixed_cases[version] = version.test_case_versions.where(status: 3).to_a

    #   @version_links[version] = version_url(version.number)
    #   @case_counts[version] = version.test_case_versions.count
    #   @computer_counts[version] = {total: version.computers_count}
    #   @pass_counts[version] = {}
    #   @fail_counts[version] = {}
    #   @case_links[version] = {}
    #   @checksum_counts[version] = {}

    #   version.test_case_versions.each do |tcv|
    #     @pass_counts[version][tcv] = tcv.test_instances.where(passed: true).count
    #     @fail_counts[version][tcv] = tcv.test_instances.where(passed: false).count
    #     @computer_counts[version][tcv] = tcv.computer_count
    #     @case_links[version][tcv] = test_case_version_url(version.number, tcv.test_case.name)
    #     # this has to do another database hit, so only do it if we need to
    #     if tcv.status >= 2
    #       # total number of distinct non-nil, non-empty checksum strings
    #       @checksum_counts[version][tcv] = tcv.unique_checksum_count
    #     end
    #   end
    # end

    # @failing_versions = TestInstance.failing_versions_since(start_date)
    # @passing_versions = TestInstance.passing_versions_since(start_date)
    # @mixed_versions = []
    # @version_links = {}
    # @computer_counts = {}
    # @case_counts = {}
    # @failing_cases = {}
    # @mixed_cases = {}
    # @pass_counts = {}
    # @fail_counts = {}
    # @case_links = {}

    # unless @failing_versions.empty?
    #   @failing_versions.each do |version|
    #     @failing_cases[version] = TestInstance.failing_cases_since(start_date, version)
    #     @version_links[version] = version_url(version.number)
    #     @computer_counts[version] = {total: version.computers.uniq.length}
    #     @case_links[version] = {}
    #     @mixed_cases[version] = []
    #     @pass_counts[version] = {}
    #     @fail_counts[version] = {}
    #   end
    #   # ornery links from SendGrid... doing this the hard way
    #   @failing_cases.each do |version, cases|
    #     cases.uniq.each do |test_case|
    #       @case_links[version][test_case] =
    #         test_case_url(test_case, version: version.number)
    #       @computer_counts[version][test_case] =
    #         test_case.version_computers(version).uniq.count

    #       # move mixed cases from @failing_cases to @mixed_cases
    #       cases.select do |test_case|
    #         test_case.version_status(version) == 2
    #       end.each do |test_case|
    #         # case is actually MIXED, so move to mixed_cases hash
    #         @mixed_cases[version].append(test_case)
    #         @failing_cases[version].delete(test_case)
    #         @pass_counts[version][test_case] = test_case.test_instances.where(
    #           version: version, passed: true
    #         ).count
    #         @fail_counts[version][test_case] = test_case.test_instances.where(
    #           version: version, passed: false
    #         ).count
    #       end
    #     end
    #     @case_counts[version] = version.test_cases.uniq.count
    #     unless @mixed_cases[version].empty?
    #       @mixed_versions.append(version)
    #     end
    #   end
    #   # throw mixed versions out so they don't appear twice
    #   @failing_versions.reject! { |version| @mixed_versions.include? version}
    # end

    # unless @passing_versions.empty?
    #   @passing_versions.each do |version|
    #     @version_links[version] = version_url(version.number)
    #     @computer_counts[version] = {total: version.computers.uniq.count}
    #     @case_counts[version] = version.test_cases.uniq.count
    #   end
    # end

    # gather sender, recipient(s), subject, and body before composing email
    from = Email.new(email: 'mesa-developers@lists.mesastar.org')
    # to = Email.new(email: 'mesa-developers@lists.mesastar.org')
    to = Email.new(email: 'wmwolf@asu.edu', name: 'Bill Wolf')
    subject = "MesaTestHub Report #{Date.today}"
    # subject line shows latest failing version, if there is one
    # if !@failing_versions.empty?
    #   subject = "Failing tests in revision #{@failing_versions.max}"
    #   subject += ' and others' if @failing_versions.length > 1
    # # no failing tests: say how many versions have passed
    # elsif !@passing_versions.empty?
    #   subject = "#{@passing_versions.length} versions with all tests passing"
    # # no tests at all... send a worthless e-mail so we know it's working
    # else
    #   subject = 'No tests submitted in the last 24 hours.'
    # end
    html_content = ApplicationController.render(
      template: 'morning_mailer/morning_email.html.erb',
      layout: 'mailer',
      # assigns: { failing_versions: @failing_versions,
      #            passing_versions: @passing_versions,
      #            mixed_versions: @mixed_versions,
      #            failing_cases: @failing_cases, mixed_cases: @mixed_cases,
      #            fail_counts: @fail_counts, pass_counts: @pass_counts,
      #            computer_counts: @computer_counts, case_counts: @case_counts,
      #            host: @host, root_url: root_url, version_links: @version_links,
      #            case_links: @case_links, checksum_cases: @checksum_cases,
      #            mixed_checksums_versions: @mixed_checksums_versions,
      #            checksum_counts: @checksum_counts }
      assigns: { version_data: @version_data,
                 versions_tested: @versions_tested,
                 make_red: @make_red,
                 make_yellow: @make_yellow,
                 make_green: @make_green,
                 make_blue: @make_blue,
                 root_url: root_url
               }
    )
    # text_content = ApplicationController.render(
    #   template: 'morning_mailer/morning_email.text.erb',
    #   layout: 'mailer',
    #   assigns: { failing_versions: @failing_versions,
    #              passing_versions: @passing_versions,
    #              mixed_versions: @mixed_versions,
    #              failing_cases: @failing_cases, mixed_cases: @mixed_cases,
    #              fail_counts: @fail_counts, pass_counts: @pass_counts,
    #              computer_counts: @computer_counts, case_counts: @case_counts,
    #              host: @host, root_url: root_url, version_links: @version_links,
    #              case_links: @case_links, checksum_cases: @checksum_cases,
    #              mixed_checksums_versions: @mixed_checksums_versions,
    #              checksum_counts: @checksum_counts }
    # )

    # compose e-mail
    email = Mail.new
    email.from = from
    email.subject = subject
    per = Personalization.new
    per.add_to(to)
    email.add_personalization(per)

    # due to SendGrid weirdness, plain text MUST come first or it won't send
    # email.add_content(Content.new(type: 'text/plain', value: text_content))
    email.add_content(Content.new(type: 'text/html', value: html_content))

    # send the message
    @client.mail._('send').post(request_body: email.to_json)
  end
end
