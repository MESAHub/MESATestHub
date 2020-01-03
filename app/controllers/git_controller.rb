class GitController < ApplicationController
  
  # set up the repository with rugged bindings
  def mesa_repo
    Rugged::Repository.new(Rails.root.join('public', 'mesa-git'))
  end

  # download fresh data from origin
  def update
    mesa_repo.fetch
  end

end
