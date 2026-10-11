#!/usr/bin/env bash
set -o errexit

# Seed once on empty catalog, then boot Sidekiq + Puma together (single Render web service).
# Recolor is not started here. The Rails client launches the project venv on
# 127.0.0.1:8000 for the first colorway request, so the storefront does not
# pay for OpenCV on every boot of the 512MB instance.
bundle exec rails runner 'load "db/seeds.rb" if defined?(Store) && Store.count.zero?'

bundle exec sidekiq -C config/sidekiq.yml &
exec bundle exec puma -C config/puma.rb
