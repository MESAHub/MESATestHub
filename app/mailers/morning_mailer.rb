class MorningMailer < ApplicationMailer
  # include SendGrid

  # def initialize
  #   @client = SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY']).client
  # end
  
  RELEASE_DATES = ['2021-12-15'].map do |date_str|
    Date.parse(date_str)
  end.freeze

  def countdown_days
    RELEASE_DATES.each do |release_date|
      if Date.today < release_date
        return (release_date - Date.today).to_i
      end
    end
    # if there are no upcoming release days, return nil
    nil
  end

  def countdown_color
    days_left = countdown_days
    return nil unless days_left
    case days_left
    when 0..7 then :red
    when 7..28 then :yellow
    else
      :green
    end
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

  # same as 2, but using basic smtp; no sendgrid secret sauce
  def morning_email_3
    # improves on old method by calculating slow/inefficient cases by looking
    # at performance relative to average _and_ sandard deviations.

    # Gather all the commits, agnostic of what branch(es) they belong to
    # sort them all in order of most recent to oldest
    start_date = 1.day.ago
    commit_ids = TestInstance.where(created_at: start_date..DateTime.now)
                             .pluck(:commit_id).uniq
    @commits_tested = Commit.includes(test_case_commits: :test_case).find(commit_ids)
    @commits_tested.sort! { |a, b| -(a.commit_time <=> b.commit_time) }

    # Assign commits to their various branches. A commit might belong to more
    # than one branch, and that's okay; it won't result in duplicate db hits
    # since they're already loaded
    branch_ids = BranchMembership.where(commit_id: commit_ids)
                                 .pluck(:branch_id).uniq
    @branch_data = {}
    branch_ids.each do |branch_id|
      this_branch = Branch.includes(:commits).find(branch_id)
      # sorting is the same as @commits_tested, but we only include commits
      # that are part of the branch.
      @branch_data[this_branch] = @commits_tested.select do |commit|
        this_branch.commits.include? commit
      end
    end

    # make sure the main is the first branch displayed, if at all
    @ordered_branches = @branch_data.keys
    main_loc = @ordered_branches.map(&:id).index(Branch.main.id)
    if main_loc
      @ordered_branches.insert(
        0, @ordered_branches.delete(@ordered_branches[main_loc])
      )
    end

    @commit_data = {}

    @commits_tested.each do |commit|
      test_case_commits = commit.test_case_commits.to_a
      res = {}
      res[:status] = case commit.status
                     when 3 then :mixed
                     when 2 then :checksums
                     when 1 then :failing
                     when 0 then :passing
                     else
                       :other
                     end
      res[:tested_count] = (commit.passed_count + commit.failed_count +
                            commit.mixed_count + commit.checksum_count)
      res[:computer_counts] = { total: commit.computer_count }
      res[:failing_cases] = test_case_commits.select { |tcc| tcc.status == 1 }
      res[:checksum_cases] = test_case_commits.select { |tcc| tcc.status == 2 }
      res[:mixed_cases] = test_case_commits.select { |tcc| tcc.status == 3 }
      res[:pass_counts] = {}
      res[:fail_counts] = {}
      res[:checksum_counts] = {}

      test_case_commits.each do |tcc|
        res[:computer_counts][tcc] = tcc.computer_count
        res[:checksum_counts][tcc] = tcc.checksum_count if tcc.status >= 2
        if tcc.status >= 3
          res[:pass_counts][tcc] = tcc.test_instances.where(passed: true).count
          res[:fail_counts][tcc] = tcc.test_instances.where(passed: false).count
        end
      end

      @commit_data[commit] = res
    end
    @make_green = "style='color: rgb(0, 153, 51)'".html_safe
    @make_yellow = "style= 'color: rgb(255, 153, 0)'".html_safe
    @make_blue = "style= 'color: rgb(78, 114, 219)'".html_safe
    @make_red = "style='color: rgb(204, 0, 0)'".html_safe
    @make_cyan = "style='color: rgb(79, 159, 181)'".html_safe

    # set up countdown at top of the email
    @countdown_days = countdown_days
    @countdown_color = case countdown_color
    when :red then @make_red
    when :yellow then @make_yellow
    when :green then @make_green
    else
      nil      
    end

    # set up issue count
    @release_blocker_count = nil
    @release_blocker_count = Commit.api.issues(Commit.repo_path,
      labels: 'release-blocker', state: 'open').length
    @release_blocker_color = if @release_blocker_count.zero?
                               @make_green
                             else
                               @make_red
                             end

    # send the message
    mail(to: 'mesa-developers@lists.mesastar.org, p7r3d3c7y5u1u9e8@mesadevelopers.slack.com',
         subject: "MesaTestHub Report #{Date.today}")
  end

  # depth = 100
  # runtime_threshold = 4
  # memory_threshold = 4

  #,
          # get test cases that ran anomolously slow or inefficiently
          # trouble_cases: commit.problem_test_case_versions(
          #   depth: depth,
          #   memory_threshold: memory_threshold,
          #   runtime_threshold: runtime_threshold)
        # }

        # get all passing test cases that have memory or speed issues and
        # organize them by name so we can walk through the list later
        # res[:problematic_passing] = (res[:trouble_cases].keys).sort do |tcv1, tcv2|
        #   tcv1.test_case.name <=> tcv2.test_case.name
        # end.uniq

        # get useful search query links for trouble cases that show data from
        # which average and standard deviation are taken from:
        # res[:trouble_cases].keys.each do |tcv|
        #   test_case_name = tcv.test_case.name
        #   if res[:trouble_cases][tcv][:runtime]
        #     res[:trouble_cases][tcv][:runtime].each_pair do |runtime_type, runtime_hash|
        #       # walk through computers and assign link for each
        #       #
        #       runtime_hash.each_pair do |computer, computer_hash|
        #         # create url that creates the relevant search query and assign it
        #         # into the computer_hash
        #         current = computer_hash[:instance]
        #         computer_hash[:url] = 'https://testhub.mesastar.org/' + 
        #           'test_instances/search?'
        #         computer_hash[:url] += {utf8: '✓'}.to_query + '&'
        #         computer_hash[:url] += {query_text: [
        #           "version: #{current.mesa_version-depth}-#{current.mesa_version - 1}",
        #           "computer: #{computer.name}",
        #           "threads: #{current.omp_num_threads}",
        #           "compiler: #{current.compiler}",
        #           "compiler_version: #{current.compiler_version}",
        #           "test_case: #{test_case_name}",
        #           "passed: true",
        #         ].join('; ')}.to_query
        #       end
        #     end
        #   end
        #   if res[:trouble_cases][tcv][:memory]
        #     res[:trouble_cases][tcv][:memory].each_pair do |run_type, run_type_hash|
        #       run_type_hash.each_pair do |computer, computer_hash|
        #         # use search api to create link showing all more efficient test
        #         # instances in last `depth` revisions
        #         current = computer_hash[:instance]
        #         computer_hash[:url] = 'https://testhub.mesastar.org/' + 
        #           'test_instances/search?'
        #         computer_hash[:url] += {utf8: '✓'}.to_query + '&'
        #         computer_hash[:url] += {query_text: [
        #           "version: #{current.mesa_version - depth}-#{current.mesa_version - 1}",
        #           "computer: #{computer.name}",
        #           "threads: #{current.omp_num_threads}",
        #           "compiler: #{current.compiler}",
        #           "compiler_version: #{current.compiler_version}",
        #           "test_case: #{test_case_name}",
        #           "passed: true",
        #         ].join('; ')}.to_query
        #       end
        #     end
        #   end
        # end

   # gather sender, recipient(s), subject, and body before composing email
    # from = Email.new(email: 'mesa-developers@lists.mesastar.org')
    # to = Email.new(email: 'mesa-developers@lists.mesastar.org')
    # # to = Email.new(email: 'wolfwm@uwec.edu', name: 'Bill Wolf')
    # subject = "MesaTestHub Report #{Date.today}"
    # html_content = ApplicationController.render(
    #   template: 'morning_mailer/morning_email_2.html.erb',
    #   layout: 'mailer',
    #   assigns: { version_data: @version_data,
    #              versions_tested: @versions_tested,
    #              make_red: @make_red,
    #              make_yellow: @make_yellow,
    #              make_green: @make_green,
    #              make_blue: @make_blue,
    #              root_url: root_url
    #            }
    # )
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
    # email = Mail.new
    # email.from = from
    # email.subject = subject
    # per = Personalization.new
    # per.add_to(to)
    # email.add_personalization(per)

    # due to SendGrid weirdness, plain text MUST come first or it won't send
    # email.add_content(Content.new(type: 'text/plain', value: text_content))
    # email.add_content(Content.new(type: 'text/html', value: html_content))


  def morning_email_2
    # improves on old method by calculating slow/inefficient cases by looking
    # at performance relative to average _and_ sandard deviations.
    
    # first gather data from database; bail if there are no failure in the last
    # 24 hours
    start_date = 1.day.ago
    @versions_tested = Version.tested_between(start_date, DateTime.now)
    @versions_tested.sort_by! { |version| -version.number }
    @version_data = {}
    depth = 100
    runtime_threshold = 4
    memory_threshold = 4
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
        # get test cases that ran anomolously slow or inefficiently
        trouble_cases: version.problem_test_case_versions(
          depth: depth,
          memory_threshold: memory_threshold,
          runtime_threshold: runtime_threshold)
      }

      # get all passing test cases that have memory or speed issues and
      # organize them by name so we can walk through the list later
      res[:problematic_passing] = (res[:trouble_cases].keys).sort do |tcv1, tcv2|
        tcv1.test_case.name <=> tcv2.test_case.name
      end.uniq

      # get useful search query links for trouble cases that show data from
      # which average and standard deviation are taken from:
      res[:trouble_cases].keys.each do |tcv|
        test_case_name = tcv.test_case.name
        if res[:trouble_cases][tcv][:runtime]
          res[:trouble_cases][tcv][:runtime].each_pair do |runtime_type, runtime_hash|
            # walk through computers and assign link for each
            #
            runtime_hash.each_pair do |computer, computer_hash|
              # create url that creates the relevant search query and assign it
              # into the computer_hash
              current = computer_hash[:instance]
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
              ].join('; ')}.to_query
            end
          end
        end
        if res[:trouble_cases][tcv][:memory]
          res[:trouble_cases][tcv][:memory].each_pair do |run_type, run_type_hash|
            run_type_hash.each_pair do |computer, computer_hash|
              # use search api to create link showing all more efficient test
              # instances in last `depth` revisions
              current = computer_hash[:instance]
              computer_hash[:url] = 'https://testhub.mesastar.org/' + 
                'test_instances/search?'
              computer_hash[:url] += {utf8: '✓'}.to_query + '&'
              computer_hash[:url] += {query_text: [
                "version: #{current.mesa_version - depth}-#{current.mesa_version - 1}",
                "computer: #{computer.name}",
                "threads: #{current.omp_num_threads}",
                "compiler: #{current.compiler}",
                "compiler_version: #{current.compiler_version}",
                "test_case: #{test_case_name}",
                "passed: true",
              ].join('; ')}.to_query
            end
          end
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
    @make_cyan = "style='color: rgb(79, 159, 181)'".html_safe

    # gather sender, recipient(s), subject, and body before composing email
    from = Email.new(email: 'mesa-developers@lists.mesastar.org')
    to = Email.new(email: 'mesa-developers@lists.mesastar.org')
    # to = Email.new(email: 'wolfwm@uwec.edu', name: 'Bill Wolf')
    subject = "MesaTestHub Report #{Date.today}"
    html_content = ApplicationController.render(
      template: 'morning_mailer/morning_email_2.html.erb',
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
      problematic_computers_limit = 2

      # create links to relevant searches for all expansions in runtimes and
      # memory usage
      res[:problematic_passing].each do |tcv|
        test_case_name = tcv.test_case.name
        if res[:slow_cases][tcv]
          # first get rid of any runtime_types that don't have enough computers
          res[:slow_cases][tcv].each_key do |key|
            problematic_computers_count = res[:slow_cases][tcv][key].length
            if problematic_computers_count < problematic_computers_limit
              res[:slow_cases][tcv].delete(key)
            end
          end

          # walk through surviving runtime types
          res[:slow_cases][tcv].each_pair do |runtime_type, runtime_hash|
            # walk through computers and assign link for each
            #
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
          # trash whole test case version if we deleted all runtime_types for
          # not having enough computers.
          res[:slow_cases].delete(tcv) if res[:slow_cases][tcv].keys.empty? 
        end
        if res[:inefficient_cases][tcv]
          # first get rid of any run_types that don't have enough computers
          res[:inefficient_cases][tcv].each_key do |key|
            problematic_computers_count = res[:inefficient_cases][tcv][key].length
            if problematic_computers_count < problematic_computers_limit
              res[:inefficient_cases][tcv].delete(key)
            end
          end
          # walk through surviving runtime types, which all have enough
          # computers
          res[:inefficient_cases][tcv].each_pair do |run_type, run_type_hash|
            # walk through computers and assign link for each
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
          if res[:inefficient_cases][tcv].keys.empty?
            res[:inefficient_cases].delete(tcv) 
          end
        end
      end

      # only retain test cases on master list if they have slow or 
      # inefficient instances on enough computers
      res[:problematic_passing].select! do |tcv|
        res[:inefficient_cases][tcv] || res[:slow_cases][tcv]
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
    to = Email.new(email: 'mesa-developers@lists.mesastar.org')
    # to = Email.new(email: 'wmwolf@asu.edu', name: 'Bill Wolf')
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
