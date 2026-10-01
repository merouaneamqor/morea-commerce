#!/usr/bin/env bash
set -o errexit

# Seed once on empty catalog, then boot Sidekiq + Puma together (single Render web service).
bundle exec rails runner 'load "db/seeds.rb" if defined?(Store) && Store.count.zero?'

bundle exec sidekiq -C config/sidekiq.yml &
exec bundle exec puma -C config/puma.rb
