# frozen_string_literal: true

# Cookie domain is set per-request in ApplicationController so:
# - *.lvh.me (or APP_BASE_DOMAIN) share a session for super-admin store switching
# - localhost keeps a host-only cookie (a .lvh.me Domain cookie is rejected there and breaks CSRF)
Rails.application.config.session_store :cookie_store, key: "_morea_session"
