Rails.application.routes.draw do
  get 'commits/show'

  get 'commits/index'

  get 'sessions/new'

  resources :users do
    resources :computers
  end
  resources :sessions
  # resources :test_cases do
  #   resources :test_instances
  # end


  # handle push requests from github repo
  # see handling details in controllers/github_webhooks_controller.rb
  # see configuration of webhooks being sent out on actual github repo for MESA
  resources :github_webhooks, only: :create, defaults: { formats: :json }

  # for accepting new submissions (of any kind) from mesa_test
  resources :submissions, only: [:create, :show], defaults: { formats: :json }
  post 'submissions/create.json', to: 'submissions#create'

  # view one submission from a computer
  get '/computers/:computer/submissions/:id', to: 'submissions#show',
    as: 'computer_submission'

  # for viewing data for one test case and one commit
  get '/:branch/commits/:sha/test_cases/:module/:test_case',
    to: 'test_case_commits#show', as:'test_case_commit', test_case: /[^\/]+/

  # for viewing data for one test case over many commits
  get '/:branch/test_cases/:module/:test_case', to: 'test_cases#show',
  as: 'test_case', test_case: /[^\/]+/

  # put this after the test case commit matcher since this is more general
  get '/:branch/commits/:sha', to: 'commits#show', as: 'commit'
  get '/:branch/commits', to: 'commits#index', as: 'commits'

  root to: 'commits#show', sha: 'auto', branch: 'main'

  # searching test_instances (should work for remote JSON requests)
  get '/test_instances/search', to: 'test_instances#search', as: 'search_instances'
  # just for counts; for API access only to prevent disastrous data dump
  get '/test_instances/search_count', to: 'test_instances#search_count'

  get 'admin', to: 'users#admin', as: 'admin'
  get 'admin_edit_user', to: 'users#admin_edit_user', as: 'admin_edit_user'
  delete 'admin_destroy_user', to: 'users#admin_destroy_user',
                               as: 'admin_delete_user'

  get 'signup', to: 'users#new', as: 'signup'
  get 'login', to: 'sessions#new', as: 'login'
  get 'logout', to: 'sessions#destroy', as: 'logout'

  post 'check_user', to: 'sessions#check_credentials', as: 'check_user'
  post 'check_computer', to: 'computers#check_computer', as: 'check_computer'

  # index of a particular user's computers's test instances
  get 'user/:user_id/computers/:id/test_instances',
      to: 'computers#test_instances_index',
      as: 'user_computer_test_instances'

  # global list of all computers (admins only)
  get 'all_computers', to: 'computers#index_all', as: 'all_computers'

end
