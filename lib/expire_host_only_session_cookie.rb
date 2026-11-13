# frozen_string_literal: true

# Shared-domain sessions (.seallo.ma / .lvh.me) used to be host-only cookies.
# A leftover host-only _morea_session is sent alongside the domain cookie, and
# the browser keeps it when logout rewrites only the domain cookie. Expire the
# host-only copy on every response that uses a shared session domain.
class ExpireHostOnlySessionCookie
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    options = env["rack.session.options"]
    expire_host_only(headers, options, Rack::Request.new(env).ssl?) if options.respond_to?(:[]) && options[:domain].present?
    [ status, headers, body ]
  end

  private

  def expire_host_only(headers, options, secure)
    cookie = {
      value: "",
      path: "/",
      expires: Time.at(0),
      max_age: 0,
      httponly: true,
      same_site: :lax
    }
    cookie[:secure] = true if secure || options[:secure]
    Rack::Utils.set_cookie_header!(headers, options[:key] || "_morea_session", cookie)
  end
end
