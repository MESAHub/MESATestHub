# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2021_05_28_024431) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "branch_memberships", force: :cascade do |t|
    t.bigint "branch_id"
    t.bigint "commit_id"
    t.index ["branch_id"], name: "index_branch_memberships_on_branch_id"
    t.index ["commit_id"], name: "index_branch_memberships_on_commit_id"
  end

  create_table "branches", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "merged", default: false
    t.bigint "head_id"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["name"], name: "index_branches_on_name", unique: true
  end

  create_table "commits", force: :cascade do |t|
    t.string "sha", null: false
    t.string "author", null: false
    t.string "author_email", null: false
    t.text "message", null: false
    t.datetime "commit_time", null: false
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
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
    t.integer "children_count", default: 0
    t.integer "parents_count", default: 0
    t.boolean "pull_request", default: false
    t.boolean "open"
    t.index ["sha"], name: "index_commits_on_sha", unique: true
    t.index ["short_sha"], name: "index_commits_on_short_sha", unique: true
  end

  create_table "computers", force: :cascade do |t|
    t.string "name", null: false
    t.string "platform"
    t.string "processor"
    t.integer "ram_gb"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.bigint "user_id"
    t.index ["name"], name: "index_computers_on_name", unique: true
    t.index ["user_id"], name: "index_computers_on_user_id"
  end

  create_table "inlist_data", force: :cascade do |t|
    t.string "name"
    t.float "val"
    t.bigint "instance_inlist_id"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["instance_inlist_id"], name: "index_inlist_data_on_instance_inlist_id"
  end

  create_table "instance_inlists", force: :cascade do |t|
    t.string "inlist"
    t.float "runtime_minutes"
    t.integer "retries"
    t.integer "steps"
    t.bigint "test_instance_id"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
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

  create_table "submissions", force: :cascade do |t|
    t.boolean "compiled"
    t.boolean "entire"
    t.bigint "commit_id"
    t.bigint "computer_id"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.boolean "empty", default: false
    t.string "compiler"
    t.string "compiler_version"
    t.string "sdk_version"
    t.string "math_backend"
    t.string "platform_version"
    t.index ["commit_id"], name: "index_submissions_on_commit_id"
    t.index ["computer_id"], name: "index_submissions_on_computer_id"
  end

  create_table "test_case_commits", force: :cascade do |t|
    t.integer "status", default: -1
    t.integer "submission_count", default: 0
    t.integer "computer_count", default: 0
    t.datetime "last_tested"
    t.bigint "commit_id", null: false
    t.bigint "test_case_id", null: false
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.integer "checksum_count", default: 0
    t.integer "passed_count", default: 0
    t.integer "failed_count", default: 0
    t.index ["commit_id"], name: "index_test_case_commits_on_commit_id"
    t.index ["test_case_id"], name: "index_test_case_commits_on_test_case_id"
  end

  create_table "test_cases", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
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
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
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
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.string "time_zone", default: "Pacific Time (US & Canada)"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "branches", "commits", column: "head_id"
  add_foreign_key "inlist_data", "instance_inlists"
  add_foreign_key "instance_inlists", "test_instances"
  add_foreign_key "submissions", "commits"
  add_foreign_key "submissions", "computers"
  add_foreign_key "test_case_commits", "commits"
  add_foreign_key "test_case_commits", "test_cases"
  add_foreign_key "test_instances", "computers"
  add_foreign_key "test_instances", "test_cases"
end
