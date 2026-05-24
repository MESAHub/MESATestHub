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
  post 'submissions/create.json', to: 'submissions#create'
  get 'submissions/request_commit.json', to: 'submissions#request_commit'
  resources :submissions, only: [:create, :show], defaults: { formats: :json }

  # view one submission from a computer
  get '/computers/:computer/submissions/:id', to: 'submissions#show',
    as: 'computer_submission'

  # Phase 4 modern-layout preview surface. Must mount BEFORE the
  # `/:branch/commits` catch-all below, otherwise the path constraint
  # `branch: /.*/` swallows `dev/preview/commits` with branch="dev/preview".
  # Dev/test only — see DevPreviewController.
  if Rails.env.development? || Rails.env.test?
    get 'dev/preview', to: 'dev_preview#index', as: 'dev_preview'
    get 'dev/preview/not_found', to: 'dev_preview#not_found',
        as: 'dev_preview_not_found'
    get 'dev/preview/commits', to: 'dev_preview#commits',
        as: 'dev_preview_commits'
  end

  # Per-test log proxy + HEAD probe. Same pattern as the commit-
  # level build_log routes below: a narrow allow-list so only logs
  # for a (commit, computer, test) actually represented in our
  # submission data are reachable. `:type` is constrained to the
  # three log files MESA test instances produce — out (stdout),
  # mk (build), err (stderr). Must mount BEFORE the catch-all
  # test_case_commit_path that follows.
  get '/:branch/commits/:sha/test_logs/:module/:test_case/:computer/:type',
      to: 'test_case_commits#log',
      as: 'test_case_commit_log',
      constraints: { branch: /.*/, sha: /[a-f0-9]+/,
                     test_case: /[^\/]+/, computer: /[^\/]+/ }

  # Cheap HEAD-only "anything-at-all" probe per (commit, computer,
  # test). Used by the per-row "logs ↗" link to hide itself when
  # the upstream has nothing for that computer + test, and by the
  # Logs-tab strip to disable the whole tab when nothing exists
  # for any computer. Cached server-side.
  get '/:branch/commits/:sha/test_logs_status/:module/:test_case/:computer',
      to: 'test_case_commits#log_status',
      as: 'test_case_commit_log_status',
      constraints: { branch: /.*/, sha: /[a-f0-9]+/,
                     test_case: /[^\/]+/, computer: /[^\/]+/ }

  # for viewing data for one test case and one commit
  get '/:branch/commits/:sha/test_cases/:module/:test_case',
    to: 'test_case_commits#show', as:'test_case_commit',
    constraints: {test_case: /[^\/]+/, branch: /.*/}


  # for viewing data for one test case over many commits
  get '/:branch/test_cases/:module/:test_case', to: 'test_cases#show',
  as: 'test_case', constraints: {test_case: /[^\/]+/, branch: /.*/}

  # Build/test log proxy. Fetches the Flatiron-hosted log over HTTPS
  # and returns it as plain text so the Logs tab can render in the
  # page without CORS shenanigans. See CommitsController#build_log
  # for the validation + bytes cap. Must mount BEFORE the catch-all
  # `:branch/commits/:sha` route below.
  get '/:branch/commits/:sha/build_log/:computer',
      to: 'commits#build_log',
      as: 'commit_build_log',
      constraints: { branch: /.*/, sha: /[a-f0-9]+/, computer: /[^\/]+/ }

  # Cheap HEAD-only availability probe for the Logs tab. Tells the
  # client whether the upstream log exists so the tab can disable
  # itself before the user wastes a click. Cached server-side.
  get '/:branch/commits/:sha/build_log_status/:computer',
      to: 'commits#build_log_status',
      as: 'commit_build_log_status',
      constraints: { branch: /.*/, sha: /[a-f0-9]+/, computer: /[^\/]+/ }

  # put this after the test case commit matcher since this is more general
  get '/:branch/commits/:sha', to: 'commits#show', as: 'commit', constraints: {branch: /.*/}
  get '/:branch/commits', to: 'commits#index', as: 'commits', constraints: {branch: /.*/}

  # for API access to nearby commits/pull requests for a branch/commit
  get '/commits/nearby_commits.json', to: 'commits#nearby_commits'

  root to: 'commits#show', sha: 'head', branch: 'main'

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

  # Bulk-delete a set of submissions from a computer. Drives the
  # "Delete selected" flow on computers#show. Authorization (user
  # owns the computer, or admin) lives in the controller. See
  # ComputersController#destroy_submissions for the IDOR-safe
  # scoping and the BULK_DESTROY_LIMIT cap.
  delete 'users/:user_id/computers/:id/submissions',
         to: 'computers#destroy_submissions',
         as: 'destroy_computer_submissions'

  # global list of all computers (admins only)
  get 'all_computers', to: 'computers#index_all', as: 'all_computers'

end
