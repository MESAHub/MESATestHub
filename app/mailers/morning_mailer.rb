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
    @failing_versions = TestInstance.failing_versions_since(start_date)
    @passing_versions = TestInstance.passing_versions_since(start_date)
    @mixed_versions = []
    @version_links = {}
    @computer_counts = {}
    @case_counts = {}
    @failing_cases = {}
    @mixed_cases = {}
    @pass_counts = {}
    @fail_counts = {}
    @case_links = {}
    unless @failing_versions.empty?
      @failing_versions.each do |version|
        @failing_cases[version] = TestInstance.failing_cases_since(start_date, version)
        @version_links[version] = version_url(version.number)
        @computer_counts[version] = {total: version.computers.uniq.length}
      end
      # ornery links from SendGrid... doing this the hard way
      @failing_cases.each do |version, cases|
        @case_links[version] = {}
        @mixed_cases[version] = []
        cases.each do |test_case|
          @case_links[version][test_case] =
            test_case_url(test_case, version: version.number)
          @computer_counts[version][test_case] =
            test_case.version_computers(version).count

          # move mixed cases from @failing_cases to @mixed_cases
          cases.select do |this_case|
            this_case.version_status(version) == 2
          end.each do |this_case|
            # case is actually MIXED, so move to mixed_cases hash
            @mixed_cases[version].append(this_case)
            @failing_cases[version].delete(this_case)
            @pass_counts[version] ||= {}
            @fail_counts[version] ||= {}
            @pass_counts[version][this_case] = this_case.test_instances.where(
              version: version, passed: true
            ).count
            @fail_counts[version][this_case] = this_case.test_instances.where(
              version: version, passed: false
            ).count
          end
        end
        @case_counts[version] = version.test_cases.count
        unless @mixed_cases[version].empty?
          @mixed_versions.append(version)
          @failing_versions.delete(version)
        end
      end
    end

    unless @passing_versions.empty?
      @passing_versions.each do |version|
        @version_links[version] = version_url(version.number)
        @computer_counts[version] = version.computers.uniq.count
        @case_counts[version] = version.test_cases.count
      end
    end

    # gather sender, recipient(s), subject, and body before composing email
    from = Email.new(email: 'mesa-developers@lists.mesastar.org')
    # to = Email.new(email: 'mesa-developers@lists.mesastar.org')
    to = Email.new(email: 'wmwolf@asu.edu', name: 'Bill Wolf')
    subject = ''
    # subject line shows latest failing version, if there is one
    if !@failing_versions.empty?
      subject = "Failing tests in revision #{@failing_versions.max}"
      subject += ' and others' if @failing_versions.length > 1
    # no failing tests: say how many versions have passed
    elsif !@passing_versions.empty?
      subject = "#{@passing_versions.length} versions with all tests passing"
    # no tests at all... send a worthless e-mail so we know it's working
    else
      subject = 'No tests submitted in the last 24 hours.'
    end
    html_content = ApplicationController.render(
      template: 'morning_mailer/morning_email.html.erb',
      layout: 'mailer',
      assigns: { failing_versions: @failing_versions,
                 passing_versions: @passing_versions,
                 failing_cases: @failing_cases, mixed_cases: @mixed_cases,
                 fail_counts: @fail_counts, pass_counts: @pass_counts,
                 computer_counts: @computer_counts, case_counts: @case_counts,
                 host: @host, root_url: root_url, version_links: @version_links,
                 case_links: @case_links }
    )
    text_content = ApplicationController.render(
      template: 'morning_mailer/morning_email.text.erb',
      layout: 'mailer',
      assigns: { failing_versions: @failing_versions,
                 passing_versions: @passing_versions,
                 failing_cases: @failing_cases, mixed_cases: @mixed_cases,
                 fail_counts: @fail_counts, pass_counts: @pass_counts,
                 computer_counts: @computer_counts, case_counts: @case_counts,
                 host: @host, root_url: root_url, version_links: @version_links,
                 case_links: @case_links }
    )

    # compose e-mail
    email = Mail.new
    email.from = from
    email.subject = subject
    per = Personalization.new
    per.add_to(to)
    email.add_personalization(per)

    # due to SendGrid weirdness, plain text MUST come first or it won't send
    email.add_content(Content.new(type: 'text/plain', value: text_content))
    email.add_content(Content.new(type: 'text/html', value: html_content))

    # send the message
    @client.mail._('send').post(request_body: email.to_json)
  end
end
