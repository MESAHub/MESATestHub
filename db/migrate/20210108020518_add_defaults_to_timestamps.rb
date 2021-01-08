class AddDefaultsToTimestamps < ActiveRecord::Migration[6.0]
  def change
    change_column_default :branches, :created_at, from: nil, to: ->{ 'now()' }
    change_column_default :branches, :updated_at, from: nil, to: ->{ 'now()' }

    change_column_default :commit_relations, :created_at, from: nil, to: ->{ 'now()' }
    change_column_default :commit_relations, :updated_at, from: nil, to: ->{ 'now()' }

    change_column_default :commits, :created_at, from: nil, to: ->{ 'now()' }
    change_column_default :commits, :updated_at, from: nil, to: ->{ 'now()' }

    change_column_default :computers, :created_at, from: nil, to: ->{ 'now()' }
    change_column_default :computers, :updated_at, from: nil, to: ->{ 'now()' }

    change_column_default :inlist_data, :created_at, from: nil, to: ->{ 'now()' }
    change_column_default :inlist_data, :updated_at, from: nil, to: ->{ 'now()' }

    change_column_default :instance_inlists, :created_at, from: nil, to: ->{ 'now()' }
    change_column_default :instance_inlists, :updated_at, from: nil, to: ->{ 'now()' }

    change_column_default :submissions, :created_at, from: nil, to: ->{ 'now()' }
    change_column_default :submissions, :updated_at, from: nil, to: ->{ 'now()' }

    change_column_default :test_case_commits, :created_at, from: nil, to: ->{ 'now()' }
    change_column_default :test_case_commits, :updated_at, from: nil, to: ->{ 'now()' }

    change_column_default :test_cases, :created_at, from: nil, to: ->{ 'now()' }
    change_column_default :test_cases, :updated_at, from: nil, to: ->{ 'now()' }

    change_column_default :test_instances, :created_at, from: nil, to: ->{ 'now()' }
    change_column_default :test_instances, :updated_at, from: nil, to: ->{ 'now()' }

    change_column_default :users, :created_at, from: nil, to: ->{ 'now()' }
    change_column_default :users, :updated_at, from: nil, to: ->{ 'now()' }
  end
end
