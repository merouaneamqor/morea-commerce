# frozen_string_literal: true

# Permanent redirect from the retired ollazen.com hosts onto seallo.ma.
# Keeps path + query, and maps tenant subdomains: morea.ollazen.com → morea.seallo.ma.
class LegacyDomainRedirect
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    return @app.call(env) if skip?(request)

    legacy = legacy_domain
    canonical = canonical_domain
    return @app.call(env) if legacy.blank? || canonical.blank? || legacy == canonical

    host = request.host.to_s.downcase
    target_host = rewritten_host(host, legacy, canonical)
    return @app.call(env) unless target_host

    location = "https://#{target_host}#{request.fullpath}"
    [ 301, { "Location" => location, "Content-Type" => "text/plain" }, [ "Moved Permanently\n" ] ]
  end

  private

  def skip?(request)
    request.path == "/up"
  end

  def legacy_domain
    ENV.fetch("LEGACY_BASE_DOMAIN", "ollazen.com").to_s.downcase.presence
  end

  def canonical_domain
    ENV["APP_BASE_DOMAIN"].to_s.downcase.presence
  end

  def rewritten_host(host, legacy, canonical)
    return canonical if host == legacy || host == "www.#{legacy}"
    return unless host.end_with?(".#{legacy}")

    slug = host.delete_suffix(".#{legacy}")
    return if slug.blank? || slug.include?(".")

    "#{slug}.#{canonical}"
  end
end
