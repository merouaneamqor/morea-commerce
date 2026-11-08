# frozen_string_literal: true

# Cookie domain is set per-request in ApplicationController so:
# - *.lvh.me (or APP_BASE_DOMAIN) share a session for super-admin store switching
# - localhost keeps a host-only cookie (a .lvh.me Domain cookie is rejected there and breaks CSRF)
#
# expire_after keeps the cookie after the browser or installed admin app is closed.
# Without it, Rack writes a session cookie and PWA/home-screen launches look signed out.
Rails.application.config.session_store :cookie_store, key: "_morea_session", expire_after: 30.days
