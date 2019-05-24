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
    @version_data = {}
    depth = 50
    runtime_percent = 30.0
    memory_percent = 10.0
    @versions_tested.each do |version|
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
        checksum_counts: {},
        # get test cases that have slowed down in recent versions
        slow_cases: version.slow_test_case_versions(
          depth: depth,
          percent: runtime_percent
        ),
        # get test cases that have consumed more memory in recent versions
        inefficient_cases: version.inefficient_test_case_versions(
          depth: depth,
          percent: memory_percent
        )
      }        

      # get all passing test cases that have memory or speed issues and
      # organize them by name so we can walk through the list later
      res[:problematic_passing] = (res[:slow_cases].keys +
        res[:inefficient_cases].keys).sort do |tcv1, tcv2|
        tcv1.test_case.name <=> tcv2.test_case.name
      end.uniq

      # only consider a test case problematic if it has memory and/or runtime
      # issues on at least two computers
      problematic_computer_limit = 2

      # create links to relevant searches for all expansions in runtimes and
      # memory usage
      res[:problematic_passing].each do |tcv|
        test_case_name = tcv.test_case.name
        if res[:slow_cases][tcv]
          # walk through runtime types
          res[:slow_cases][tcv].each_pair do |runtime_type, runtime_hash|
            # walk through computers and assign link for each
            # throw whole runtime_type out if there isn't more than one
            # computer
            
            if runtime_hash.keys.length < problematic_computer_limit
              res[:slow_cases][tcv].delete(runtime_type)
            else
              # what to put in the search query
              runtime_query = case runtime_type
              when :rn then 'rn_runtime'
              when :re then 're_runtime'
              else
                'runtime'
              end
              # what to ask the model for
              runtime_attribute = case runtime_type
              when :rn then :runtime_seconds
              when :re then :re_time
              else
                :total_runtime_seconds
              end
              runtime_hash.each_pair do |computer, computer_hash|
                # create url that creates the relevant search query and assign it
                # into the computer_hash
                current = computer_hash[:current]
                max_runtime = (current.send(runtime_attribute) *
                               (1.0 / (1.0 + (runtime_percent / 100.0))))
                max_runtime = sprintf('%.1f', max_runtime)

                computer_hash[:url] = 'https://testhub.mesastar.org/' + 
                  'test_instances/search?'
                computer_hash[:url] += {utf8: '✓'}.to_query + '&'

                computer_hash[:url] += {query_text: [
                  "version: #{current.mesa_version-depth}-#{current.mesa_version - 1}",
                  "computer: #{computer.name}",
                  "threads: #{current.omp_num_threads}",
                  "compiler: #{current.compiler}",
                  "compiler_version: #{current.compiler_version}",
                  "test_case: #{test_case_name}",
                  "passed: true",
                  "#{runtime_query}: 0.01-#{max_runtime}"
                ].join('; ')}.to_query
                # hold on to current and better times in seconds
                computer_hash[:current_time] = current.send(runtime_attribute)
                computer_hash[:better_time] = computer_hash[:better].send(
                  runtime_attribute)
              end
            end
          end
          # trash whole test case version if we deleted all runtime_types for
          # not having enough computers.
          res[:slow_cases].delete(tcv) if res[:slow_cases][tcv].keys.empty? 
        end
        if res[:inefficient_cases][tcv]
          # walk through runtime types
          res[:inefficient_cases][tcv].each_pair do |run_type, run_type_hash|
            # walk through computers and assign link for each

            if run_type_hash.keys.length < problematic_computer_limit
              res[:inefficient_cases][tcv].delete(run_type)
            else
              # what to put in the search query
              memory_query = case run_type
              when :rn then 'rn_RAM'
              when :re then 're_RAM'
              else
                nil
              end
              # what to use to get current value from the model
              memory_attribute = (run_type.to_s + '_mem').to_sym
              run_type_hash.each_pair do |computer, computer_hash|
                # create relevant search query and assign it into the 
                # computer_hash
                current = computer_hash[:current]
                # this needs to be in GB for the search API
                max_RAM = (current.send(memory_attribute) *
                           (1.0 / (1.0 + (memory_percent / 100.0))) / 
                           (1.024e3 ** 2)
                          )
                max_RAM = sprintf('%.2f', max_RAM)
                # use search api to create link showing all more efficient test
                # instances in last 50 revisions
                computer_hash[:url] = 'https://testhub.mesastar.org/' + 
                  'test_instances/search?'
                computer_hash[:url] += {utf8: '✓'}.to_query + '&'
                computer_hash[:url] += {query_text: [
                  "version: #{current.mesa_version-depth}-#{current.mesa_version - 1}",
                  "computer: #{computer.name}",
                  "threads: #{current.omp_num_threads}",
                  "compiler: #{current.compiler}",
                  "compiler_version: #{current.compiler_version}",
                  "test_case: #{test_case_name}",
                  "passed: true",
                  "#{memory_query}: 0.01-#{max_RAM}"
                ].join('; ')}.to_query
                # hold on to current and better RAM in GB for view
                computer_hash[:current_RAM] = sprintf(
                  '%.2f', current.send(memory_attribute) / (1.024e3 ** 2)
                )
                computer_hash[:better_RAM] = sprintf(
                  '%.2f',
                  computer_hash[:better].send(memory_attribute) / (1.024e3 ** 2)
                )
              end
            end
          end
          if res[:inefficient_cases][tcv].keys.empty?
            res[:inefficient_cases].delete(tcv) 
          end
        end
        # remove test case from overall list if they don't show slowing or
        # memory bloat on enough computers.
        unless res[:inefficient_cases][tcv] || res[:slow_cases][tcv]
          res[:problematic_passing].delete(tcv)
        end
      end
      version.test_case_versions.each do |tcv|
        res[:computer_counts][tcv] = tcv.computer_count
        if tcv.status >= 2
          res[:checksum_counts][tcv] = tcv.unique_checksum_count
        end
        if tcv.status >= 3
          res[:pass_counts][tcv] = tcv.test_instances.where(passed: true).count
          res[:fail_counts][tcv] = tcv.test_instances.where(passed: false).count
        end
        res[:case_links][tcv] = test_case_version_url(
          version.number, tcv.test_case.name
        )
      end
      @version_data[version] = res
    end
    @make_green = "style='color: rgb(0, 153, 51)'".html_safe
    @make_yellow = "style= 'color: rgb(255, 153, 0)'".html_safe
    @make_blue = "style= 'color: rgb(78, 114, 219)'".html_safe
    @make_red = "style='color: rgb(204, 0, 0)'".html_safe

    # gather sender, recipient(s), subject, and body before composing email
    from = Email.new(email: 'mesa-developers@lists.mesastar.org')
    # to = Email.new(email: 'mesa-developers@lists.mesastar.org')
    to = Email.new(email: 'wmwolf@asu.edu', name: 'Bill Wolf')
    subject = "MesaTestHub Report #{Date.today}"
    html_content = ApplicationController.render(
      template: 'morning_mailer/morning_email.html.erb',
      layout: 'mailer',
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
