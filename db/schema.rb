# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_05_28_195909) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_stat_statements"

  create_table "branch_memberships", force: :cascade do |t|
    t.bigint "branch_id"
    t.bigint "commit_id"
    t.index ["branch_id"], name: "index_branch_memberships_on_branch_id"
    t.index ["commit_id", "branch_id"], name: "index_branch_memberships_on_commit_id_and_branch_id", unique: true
    t.index ["commit_id"], name: "index_branch_memberships_on_commit_id"
  end

  create_table "branches", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "merged", default: false
    t.bigint "head_id"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.index ["name"], name: "index_branches_on_name", unique: true
  end

  create_table "claims", force: :cascade do |t|
    t.bigint "computer_id", null: false
    t.bigint "commit_id", null: false
    t.bigint "test_case_commit_id"
    t.string "scope", null: false
    t.string "status", default: "pending", null: false
    t.boolean "use_fpe", default: false, null: false
    t.boolean "use_full_inlists", default: false, null: false
    t.boolean "use_converge", default: false, null: false
    t.datetime "dispatched_at"
    t.datetime "expires_at", null: false
    t.datetime "fulfilled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["commit_id", "status"], name: "index_claims_on_commit_id_and_status"
    t.index ["commit_id"], name: "index_claims_on_commit_id"
    t.index ["computer_id", "status"], name: "index_claims_on_computer_id_and_status"
    t.index ["computer_id"], name: "index_claims_on_computer_id"
    t.index ["expires_at"], name: "index_claims_on_expires_at_pending", where: "((status)::text = 'pending'::text)"
    t.index ["test_case_commit_id", "status"], name: "index_claims_on_test_case_commit_id_and_status"
    t.index ["test_case_commit_id"], name: "index_claims_on_test_case_commit_id"
    t.check_constraint "scope::text = 'build'::text AND test_case_commit_id IS NULL OR scope::text = 'test'::text AND test_case_commit_id IS NOT NULL", name: "claims_scope_fk_coherence"
  end

  create_table "commit_relations", force: :cascade do |t|
    t.bigint "parent_id", null: false
    t.bigint "child_id", null: false
    t.integer "parent_index", default: 0, null: false
    t.index ["child_id", "parent_id"], name: "index_commit_relations_on_child_id_and_parent_id", unique: true
    t.index ["parent_id"], name: "index_commit_relations_on_parent_id"
  end

  create_table "commits", force: :cascade do |t|
    t.string "sha", null: false
    t.string "author", null: false
    t.string "author_email", null: false
    t.text "message", null: false
    t.datetime "commit_time", precision: nil, null: false
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.string "short_sha"
    t.string "github_url"
    t.integer "test_case_count", default: 0
    t.integer "passed_count", default: 0
    t.integer "failed_count", default: 0
    t.integer "mixed_count", default: 0
    t.integer "untested_count", default: 0
    t.integer "checksum_count", default: 0
    t.integer "complete_computer_count", default: 0
    t.integer "computer_count", default: 0
    t.integer "status", default: 0
    t.boolean "pull_request", default: false
    t.boolean "open"
    t.boolean "ci_skip", default: false, null: false
    t.boolean "wants_full_inlists", default: false, null: false
    t.boolean "wants_fpe", default: false, null: false
    t.boolean "wants_converge", default: false, null: false
    t.datetime "full_inlists_satisfied_at"
    t.datetime "fpe_satisfied_at"
    t.datetime "converge_satisfied_at"
    t.index ["sha"], name: "index_commits_on_sha", unique: true
    t.index ["short_sha"], name: "index_commits_on_short_sha", unique: true
  end

  create_table "computers", force: :cascade do |t|
    t.string "name", null: false
    t.string "platform"
    t.string "processor"
    t.integer "ram_gb"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.bigint "user_id"
    t.index ["name"], name: "index_computers_on_name", unique: true
    t.index ["user_id"], name: "index_computers_on_user_id"
  end

  create_table "inlist_data", force: :cascade do |t|
    t.string "name"
    t.float "val"
    t.bigint "instance_inlist_id"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.index ["instance_inlist_id"], name: "index_inlist_data_on_instance_inlist_id"
  end

  create_table "instance_inlists", force: :cascade do |t|
    t.string "inlist"
    t.float "runtime_minutes"
    t.integer "retries"
    t.integer "steps"
    t.bigint "test_instance_id"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "solver_calls_failed"
    t.integer "solver_iterations"
    t.integer "solver_calls_made"
    t.integer "redos"
    t.float "log_rel_run_E_err"
    t.integer "order", default: 0
    t.integer "model_number", default: -1
    t.float "star_age", default: -1.0
    t.integer "num_retries", default: -1
    t.index ["test_instance_id"], name: "index_instance_inlists_on_test_instance_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "submissions", force: :cascade do |t|
    t.boolean "compiled"
    t.boolean "entire"
    t.bigint "commit_id"
    t.bigint "computer_id"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.boolean "empty", default: false
    t.string "compiler"
    t.string "compiler_version"
    t.string "sdk_version"
    t.string "math_backend"
    t.string "platform_version"
    t.bigint "claim_id"
    t.datetime "started_at"
    t.boolean "use_fpe", default: false, null: false
    t.boolean "use_full_inlists", default: false, null: false
    t.boolean "use_converge", default: false, null: false
    t.index ["claim_id"], name: "index_submissions_on_claim_id"
    t.index ["commit_id"], name: "index_submissions_on_commit_id"
    t.index ["computer_id", "created_at"], name: "index_submissions_on_computer_id_and_created_at"
    t.index ["computer_id"], name: "index_submissions_on_computer_id"
  end

  create_table "test_case_commits", force: :cascade do |t|
    t.integer "status", default: -1
    t.integer "submission_count", default: 0
    t.integer "computer_count", default: 0
    t.datetime "last_tested", precision: nil
    t.bigint "commit_id", null: false
    t.bigint "test_case_id", null: false
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.integer "checksum_count", default: 0
    t.integer "passed_count", default: 0
    t.integer "failed_count", default: 0
    t.index ["commit_id"], name: "index_test_case_commits_on_commit_id"
    t.index ["test_case_id"], name: "index_test_case_commits_on_test_case_id"
  end

  create_table "test_cases", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.string "module"
    t.index ["name", "module"], name: "index_test_cases_on_name_and_module"
  end

  create_table "test_instances", force: :cascade do |t|
    t.integer "runtime_seconds"
    t.integer "omp_num_threads"
    t.string "compiler"
    t.string "compiler_version"
    t.string "platform_version"
    t.boolean "passed", null: false
    t.bigint "computer_id", null: false
    t.bigint "test_case_id", null: false
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.string "success_type"
    t.string "failure_type"
    t.integer "steps"
    t.integer "retries"
    t.integer "backups"
    t.text "summary_text"
    t.integer "diff", default: 2
    t.string "checksum"
    t.string "computer_name"
    t.string "computer_specification"
    t.integer "total_runtime_seconds"
    t.integer "re_time"
    t.integer "mem_rn"
    t.integer "mem_re"
    t.bigint "commit_id"
    t.bigint "test_case_commit_id"
    t.bigint "submission_id"
    t.string "sdk_version"
    t.string "math_backend"
    t.float "runtime_minutes"
    t.integer "solver_iterations"
    t.integer "solver_calls_failed"
    t.integer "solver_calls_made"
    t.integer "redos"
    t.float "log_rel_run_E_err"
    t.string "restart_checksum"
    t.string "restart_photo"
    t.boolean "run_optional"
    t.boolean "fpe_checks"
    t.float "cpu_hours", default: 0.0
    t.float "resolution_factor", default: 1.0
    t.index ["commit_id"], name: "index_test_instances_on_commit_id"
    t.index ["computer_id"], name: "index_test_instances_on_computer_id"
    t.index ["submission_id"], name: "index_test_instances_on_submission_id"
    t.index ["test_case_commit_id"], name: "index_test_instances_on_test_case_commit_id"
    t.index ["test_case_id"], name: "index_test_instances_on_test_case_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "name"
    t.string "password_digest"
    t.boolean "admin"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false
    t.string "time_zone", default: "Pacific Time (US & Canada)"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "branches", "commits", column: "head_id"
  add_foreign_key "claims", "commits"
  add_foreign_key "claims", "computers"
  add_foreign_key "claims", "test_case_commits"
  add_foreign_key "commit_relations", "commits", column: "child_id"
  add_foreign_key "commit_relations", "commits", column: "parent_id"
  add_foreign_key "computers", "users", on_delete: :cascade
  add_foreign_key "inlist_data", "instance_inlists"
  add_foreign_key "instance_inlists", "test_instances"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "submissions", "claims"
  add_foreign_key "submissions", "commits"
  add_foreign_key "submissions", "computers"
  add_foreign_key "test_case_commits", "commits"
  add_foreign_key "test_case_commits", "test_cases"
  add_foreign_key "test_instances", "computers"
  add_foreign_key "test_instances", "test_cases"
end
