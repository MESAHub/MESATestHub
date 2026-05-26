# Pull the Railway-hosted production Postgres into the local
# development database via pg_dump → pg_restore.  Reads the
# public TCP-proxy URL from Railway's `variables` API by default;
# accepts a manual override via the `PROD_DATABASE_URL` env var
# for when the Railway CLI isn't available.
#
# Usage:
#
#   bundle exec rake db:pull_prod
#
# Or, with the CLI not installed / a one-off URL on hand:
#
#   PROD_DATABASE_URL='postgres://...:.../railway' \
#     bundle exec rake db:pull_prod
#
# Skip the confirmation prompt (for scripted use):
#
#   OVERWRITE=1 bundle exec rake db:pull_prod
#
# The task refuses to run outside the development environment.
namespace :db do
  desc 'Pull Railway production Postgres into local development DB.'
  task pull_prod: :environment do
    unless Rails.env.development?
      abort "Refusing to run outside the development environment " \
            "(RAILS_ENV=#{Rails.env}). This task drops the local " \
            "DB; running it against test or production would be " \
            "catastrophic."
    end

    prod_url = fetch_prod_database_url
    abort 'Could not resolve a production DATABASE_PUBLIC_URL. ' \
          'Either install the Railway CLI and run `railway link`, ' \
          'or set PROD_DATABASE_URL manually.' if prod_url.nil?

    local_db = local_development_db_name
    dump_path = Rails.root.join('tmp', 'prod.dump').to_s

    puts "About to:"
    puts "  - pg_dump from production (URL hidden)"
    puts "  - drop local database `#{local_db}`"
    puts "  - pg_restore prod data into a fresh local `#{local_db}`"
    puts "  - run pending migrations"
    confirm_or_abort

    FileUtils.mkdir_p(File.dirname(dump_path))

    puts "\n→ Dumping production to #{dump_path}…"
    run_silently('pg_dump',
                 '--format=custom',
                 '--no-acl',
                 '--no-owner',
                 '--dbname', prod_url,
                 '--file', dump_path)

    puts "→ Dropping and recreating local `#{local_db}`…"
    # Use ActiveRecord's tasks so we honor whatever database.yml
    # encoding/template options are set for this app.
    Rake::Task['db:drop'].invoke
    Rake::Task['db:create'].invoke

    puts "→ Restoring dump into `#{local_db}`…"
    run_silently('pg_restore',
                 '--no-acl',
                 '--no-owner',
                 '--dbname', local_db,
                 dump_path,
                 allow_nonzero_exit: true)
    # pg_restore prints warnings to stderr (e.g. about extensions
    # we don't own) and returns non-zero even on otherwise-clean
    # restores. The dump is intact regardless; suppressing the
    # exit code prevents the warnings from looking like failures.

    puts "→ Running pending migrations…"
    Rake::Task['db:migrate'].invoke

    puts "\nDone. Local `#{local_db}` now matches Railway production."
    puts "(Dump preserved at #{dump_path} — re-restore without " \
         "re-pulling via pg_restore directly, or delete it.)"
  end
end

# Returns the production DATABASE_PUBLIC_URL, or nil if it can't be
# resolved. Tries env-var first (for users without the Railway CLI),
# then `railway variables`. Doesn't echo the URL itself.
def fetch_prod_database_url
  if (override = ENV['PROD_DATABASE_URL']).present?
    return override
  end

  service = ENV.fetch('RAILWAY_DB_SERVICE', 'Postgres')

  unless railway_cli_available?
    warn "Railway CLI not found in PATH. Either install it or set " \
         "PROD_DATABASE_URL manually."
    return nil
  end

  output = `railway variables -s #{service} --kv 2>/dev/null`
  unless $?.success?
    warn "`railway variables -s #{service}` failed. Has this repo " \
         "been linked to a Railway project (`railway link`)? Is the " \
         "Postgres service actually named `#{service}` (override " \
         "with RAILWAY_DB_SERVICE)?"
    return nil
  end

  url = output.lines
              .map { |line| line.strip.split('=', 2) }
              .find { |kv| kv.first == 'DATABASE_PUBLIC_URL' }
              &.last

  warn "Railway returned no DATABASE_PUBLIC_URL for service " \
       "`#{service}`. The Postgres service may not have its TCP " \
       "proxy enabled — check the Networking tab in Railway." if url.nil?
  url
end

def railway_cli_available?
  system('command -v railway > /dev/null 2>&1')
end

def local_development_db_name
  ActiveRecord::Base.configurations
                    .configs_for(env_name: 'development')
                    .first
                    .database
end

def confirm_or_abort
  if ENV['OVERWRITE'] == '1'
    puts 'OVERWRITE=1 set — skipping confirmation.'
    return
  end

  print "\nProceed? (yes/no) > "
  answer = $stdin.gets&.strip&.downcase
  abort 'Aborted.' unless %w[y yes].include?(answer)
end

# Runs a command without interpolating args into a shell string —
# safer when one of the args is a connection URL containing
# special characters. `allow_nonzero_exit: true` returns instead
# of aborting on nonzero status.
def run_silently(*cmd, allow_nonzero_exit: false)
  success = system(*cmd)
  return if success
  return if allow_nonzero_exit

  abort "Command failed: #{cmd.first} (exit #{$?.exitstatus})"
end
