#!/usr/bin/env bash
set -o errexit

# Seed once on empty catalog, then boot Sidekiq + Puma together (single Render web service).
# Free plan is 512Mi: prefer one Puma process, one Sidekiq process, smaller malloc arenas,
# and no YJIT unless explicitly re-enabled.
export MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"
export WEB_CONCURRENCY="${WEB_CONCURRENCY:-0}"
export SIDEKIQ_CONCURRENCY="${SIDEKIQ_CONCURRENCY:-1}"
export RUBY_YJIT_ENABLE="${RUBY_YJIT_ENABLE:-0}"

bundle exec rails runner '
  load "db/seeds.rb" if defined?(Store) && Store.count.zero?
  begin
    result = Platform::DeadJobCleanup.clear_runtime_orphans!
    puts "[boot] cleared #{result.removed} orphan Sidekiq job(s)" if result.removed.positive?
  rescue StandardError => e
    warn "[boot] orphan Sidekiq cleanup skipped: #{e.class}: #{e.message}"
  end
'

bundle exec sidekiq -C config/sidekiq.yml &
exec bundle exec puma -C config/puma.rb
