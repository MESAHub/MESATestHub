# A throwaway user, computer, and commit in the *development* database, for
# exercising mesa_test against a local testhub (mesa_test's dev/e2e
# harness drives these). Everything is tagged so teardown finds it again.
#
#   bin/rails dev:client_fixture:setup SHA=<40-char sha> \
#     TESTS=star/fake_alpha,star/fake_beta,binary/fake_gamma \
#     WANTS=optional,converge          # optional, fpe, converge, skip
#   bin/rails dev:client_fixture:report
#   bin/rails dev:client_fixture:teardown
#
# setup prints JSON: { email, password, api_key, computer, sha }. The commit
# lands on main, dated now, so build dispatch recommends it first.
module ClientFixture
  EMAIL    = 'client-fixture@example.test'.freeze
  COMPUTER = 'client-fixture'.freeze
  WANTS    = { 'optional' => :wants_full_inlists, 'fpe' => :wants_fpe,
               'converge' => :wants_converge, 'skip' => :ci_skip }.freeze

  module_function

  def guard!
    return if Rails.env.development?
    abort 'dev:client_fixture only runs against the development database.'
  end

  def commits
    Commit.where(author_email: EMAIL)
  end

  def teardown
    User.find_by(email: EMAIL)&.destroy!
    test_case_ids = TestCaseCommit.where(commit: commits).pluck(:test_case_id)
    commits.destroy_all
    # Only fake_* test cases (the harness's naming), and only once nothing
    # else uses them. delete_all rather than destroy: nothing hangs off an
    # unused test case, and TestCase#destroy trips over a stale association.
    TestCase.where(id: test_case_ids).where("name LIKE 'fake\\_%'")
            .where.not(id: TestCaseCommit.select(:test_case_id))
            .delete_all
  end
end

namespace :dev do
  namespace :client_fixture do
    desc 'Create a throwaway user/computer/commit for mesa_test end-to-end runs (development only).'
    task setup: :environment do
      ClientFixture.guard!
      ClientFixture.teardown
      sha = ENV.fetch('SHA')
      abort 'SHA must be a 40-character commit sha.' unless sha.match?(/\A\h{40}\z/)

      password = SecureRandom.hex(12)
      user = User.create!(name: 'Client Fixture', email: ClientFixture::EMAIL,
                          password: password, password_confirmation: password)
      computer = Computer.create!(name: ClientFixture::COMPUTER, user: user, platform: 'linux')
      api_key = computer.generate_api_key!

      wants = ENV.fetch('WANTS', '').split(',').map(&:strip).reject(&:empty?)
      unknown = wants - ClientFixture::WANTS.keys
      abort "Unknown WANTS: #{unknown.join(', ')}" if unknown.any?
      commit = Commit.create!(
        sha: sha, short_sha: sha[0, 7], author: 'Client Fixture',
        author_email: ClientFixture::EMAIL, message: 'client fixture commit',
        commit_time: Time.current, github_url: "https://example.test/#{sha}",
        **wants.to_h { |w| [ClientFixture::WANTS[w], true] }
      )
      BranchMembership.create!(branch: Branch.main || Branch.create!(name: 'main'), commit: commit)
      ENV.fetch('TESTS').split(',').each do |spec|
        mod, name = spec.strip.split('/', 2)
        test_case = TestCase.find_or_create_by!(module: mod, name: name)
        TestCaseCommit.create_or_find_by!(commit: commit, test_case: test_case)
      end

      puts({ email: user.email, password: password, api_key: api_key,
             computer: computer.name, sha: sha }.to_json)
    end

    desc 'Print the fixture commit\'s claims, runs, and CI-request state as JSON (development only).'
    task report: :environment do
      ClientFixture.guard!
      commit = ClientFixture.commits.first or abort 'No fixture commit; run setup first.'
      claims = Claim.where(commit: commit).includes(test_case_commit: :test_case).map do |c|
        { scope: c.scope, status: c.status,
          test: c.test_case_commit&.test_case&.then { |t| "#{t.module}/#{t.name}" },
          use_full_inlists: c.use_full_inlists, use_fpe: c.use_fpe, use_converge: c.use_converge }
      end
      runs = TestInstance.where(commit: commit).includes(:test_case).order(:id).map do |i|
        { test: "#{i.test_case.module}/#{i.test_case.name}", run_optional: i.run_optional,
          fpe_checks: i.fpe_checks, resolution_factor: i.resolution_factor, passed: i.passed }
      end
      submissions = Submission.where(commit: commit).order(:id).map do |s|
        s.slice(:empty, :entire, :compiled, :use_fpe, :use_full_inlists, :use_converge)
      end
      puts({ claims: claims, runs: runs, submissions: submissions,
             satisfied: { optional: commit.full_inlists_satisfied_at.present?,
                          fpe: commit.fpe_satisfied_at.present?,
                          converge: commit.converge_satisfied_at.present? } }.to_json)
    end

    desc 'Remove everything dev:client_fixture:setup created (development only).'
    task teardown: :environment do
      ClientFixture.guard!
      ClientFixture.teardown
      puts 'Client fixture removed.'
    end
  end
end
