# Admin session persistence

Admin sign-in uses the `_morea_session` cookie store. The cookie always carries an expiry so closing the browser or reopening the installed admin app does not drop the session.

## Behaviour

Default lifetime is 30 days (`ApplicationController::SESSION_TTL`). Checking **Remember me** stores `session[:remember_admin]` and uses 90 days (`REMEMBER_TTL`). `configure_session_cookie` re-applies domain and `expire_after` on every request so later flash or session writes keep the same durable cookie instead of collapsing to a browser-session cookie.

Password reset still bumps `session_version` and ends other live sessions. Logout clears the session. Tenant host scoping and apex workspace rules are unchanged.

## Verification

```sh
RAILS_ENV=test bundle exec rspec spec/requests/merchant_sign_in_spec.rb
```
