class CommitsController < ApplicationController
  before_action :set_commit, only: :show

  def show

  end

  def index
  end

  private

  def set_commit
    @commit = parse_sha
  end
end
