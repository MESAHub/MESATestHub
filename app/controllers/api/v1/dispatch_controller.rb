# Phase C of the dispatcher + claims feature
# (docs/dispatcher-and-claims.md). Tells a mesa_test client what to
# work on next — a commit to build, or a test to run on a commit it
# has built — and which run-time switches to use. Read-only: the
# recommendation is advice, and the client registers intent
# separately via POST /api/v1/claims (echoing `dispatched_at`).
#
# 200 with a recommendation, or 204 when there's nothing useful for
# this computer to do. The decision logic lives in WorkDispatcher.
module Api
  module V1
    class DispatchController < ApplicationController
      include ApiSubmitterAuth

      skip_before_action :authorize_user
      skip_before_action :verify_authenticity_token, only: [:create]

      def create
        return unless authenticate_submitter_computer
        return unless validate_scope
        return unless resolve_pinned_commit

        rec = WorkDispatcher.new(computer: @computer, scope: @scope, commit: @pinned_commit,
                                 capabilities: capabilities).call
        return head :no_content unless rec

        render json: recommendation_json(rec)
      end

      private

      def validate_scope
        @scope = dispatch_params[:scope].to_s
        unless Claim::SCOPES.include?(@scope)
          return api_fail(:bad_request,
                          "Invalid scope: #{@scope.inspect}. " \
                          "Must be one of #{Claim::SCOPES.inspect}.")
        end
        if @scope == 'build' && dispatch_params[:commit_sha].present?
          return api_fail(:bad_request, 'commit_sha only applies to scope=test.')
        end

        true
      end

      # scope=test may pin the commit the client just built, so the
      # recommended test is one it can actually run.
      def resolve_pinned_commit
        sha = dispatch_params[:commit_sha]
        return true if sha.blank?

        @pinned_commit = Commit.find_by(sha: sha)
        return true if @pinned_commit

        api_fail(:not_found, "Unknown commit SHA: #{sha}.")
      end

      def capabilities
        WorkDispatcher::CONFIGS.keys.index_with { |config| api_bool(dispatch_params[:"can_#{config}"]) }
      end

      def recommendation_json(rec)
        commit = rec.commit
        branch = commit.preferred_branch
        test_case = rec.test_case_commit&.test_case
        {
          commit_sha: commit.sha,
          short_sha: commit.short_sha,
          branch: branch&.name,
          scope: rec.scope,
          test_case_module: test_case&.module,
          test_case_name: test_case&.name,
          flags: rec.flag_params,
          score: rec.score,
          reasons: rec.reasons,
          dispatched_at: Time.current.iso8601,
          target_url: branch ? commit_url(branch: branch.name, sha: commit.short_sha) : nil
        }
      end

      def dispatch_params
        params.require(:dispatch).permit(:scope, :commit_sha,
                                         *WorkDispatcher::CONFIGS.keys.map { |c| :"can_#{c}" })
      end
    end
  end
end
