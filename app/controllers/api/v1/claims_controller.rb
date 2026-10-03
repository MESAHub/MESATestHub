# Phase B of the dispatcher + claims feature
# (docs/dispatcher-and-claims.md). Records a computer's intent to
# do a piece of work — either build a commit (`scope='build'`) or
# run one test case on a commit (`scope='test'`) — and starts the
# wall-clock TTL via `Claim.default_expires_at`. The dispatcher
# endpoint that *recommends* what to claim lives in Phase C and is
# deliberately separate from this one (see "Dispatch vs. claim
# creation" in the design doc).
#
# Authentication (shared with the dispatcher via ApiSubmitterAuth)
# mirrors `SubmissionsController` exactly, so `mesa_test` reuses its
# existing credential plumbing.
module Api
  module V1
    class ClaimsController < ApplicationController
      include ApiSubmitterAuth

      skip_before_action :authorize_user
      skip_before_action :verify_authenticity_token, only: [:create]

      def create
        return unless authenticate_claim
        return unless validate_scope

        if @scope == 'test'
          return unless resolve_test_case_commit
        end

        claim = Claim.new(
          computer: @computer,
          commit: @commit,
          test_case_commit: @tcc,
          scope: @scope,
          status: 'pending',
          use_fpe: bool_param(:use_fpe),
          use_full_inlists: bool_param(:use_full_inlists),
          use_converge: bool_param(:use_converge),
          dispatched_at: parse_iso_datetime(claim_params[:dispatched_at]),
          expires_at: Claim.default_expires_at(scope: @scope)
        )

        if claim.save
          render json: { claim_id: claim.id,
                         expires_at: claim.expires_at.iso8601 },
                 status: :created
        else
          render json: { error: claim.errors.full_messages.join('; ') },
                 status: :unprocessable_content
        end
      end

      private

      # Same shape as SubmissionsController#authenticate_submission:
      # verify the user, scope the computer to that user, and look
      # up the commit by SHA. Returns true on success; sets a JSON
      # error response and returns false on any failure.
      def authenticate_claim
        return false unless authenticate_submitter_computer

        @commit = Commit.find_by(sha: claim_params[:commit_sha])
        return api_fail(:not_found,
                        "Unknown commit SHA: #{claim_params[:commit_sha]}.") unless @commit

        true
      end

      def validate_scope
        @scope = claim_params[:scope].to_s
        return true if Claim::SCOPES.include?(@scope)

        api_fail(:bad_request,
                 "Invalid scope: #{@scope.inspect}. " \
                 "Must be one of #{Claim::SCOPES.inspect}.")
      end

      # For scope='test', the request carries a (module, name) pair
      # identifying the test case. Look up the matching TCC on the
      # claimed commit. Unlike the submissions path, this endpoint
      # does NOT lazily create a TCC — TCCs are guaranteed to exist
      # by the topology sync at commit ingest, so a missing one
      # means either a stale client or a test case that doesn't
      # apply to this commit, both of which the client should hear
      # about explicitly.
      def resolve_test_case_commit
        mod  = claim_params[:test_case_module].to_s
        name = claim_params[:test_case_name].to_s
        return api_fail(:bad_request,
                        'test_case_module and test_case_name are required ' \
                        'for scope=test.') if mod.empty? || name.empty?

        @tcc = @commit.test_case_commits
                       .joins(:test_case)
                       .find_by(test_cases: { module: mod, name: name })

        return true if @tcc

        api_fail(:not_found,
                 "No test case commit found for #{mod}/#{name} on " \
                 "#{@commit.short_sha}.")
      end

      def claim_params
        params.require(:claim).permit(
          :commit_sha, :scope,
          :test_case_module, :test_case_name,
          :use_fpe, :use_full_inlists, :use_converge,
          :dispatched_at
        )
      end

      # Absent means false, not unknown — claims' `use_*` columns
      # are NOT NULL and default to false.
      def bool_param(key)
        api_bool(claim_params[key])
      end

      def parse_iso_datetime(value)
        return nil if value.blank?
        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
