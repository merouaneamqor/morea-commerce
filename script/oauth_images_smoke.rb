# frozen_string_literal: true

raise "Smoke checks require the isolated test environment" unless Rails.env.test?

# OAuth authorization codes need a cache; the default test NullStore discards them.
Rails.cache = ActiveSupport::Cache::MemoryStore.new

store = Store.find_by!(slug: "morea")
client = OauthClient.register!(name: "CI MCP", redirect_uris: [ "https://chatgpt.com/connector/oauth/callback" ])
verifier = SecureRandom.urlsafe_base64(48)
challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
http = ActionDispatch::Integration::Session.new(Rails.application)
http.host! "morea.lvh.me"

code_for = lambda do
  Oauth::Codes.issue(store: store, client_id: client.client_id,
    redirect_uri: client.redirect_uris.first, code_challenge: challenge)
end
exchange = lambda do |code, client_id|
  http.post "/oauth/token", params: { grant_type: "authorization_code", code: code,
    client_id: client_id, redirect_uri: client.redirect_uris.first, code_verifier: verifier }
end
exchange.call(code_for.call, nil)
raise "Missing client_id accepted" unless http.response.status == 400
code = code_for.call
exchange.call(code, client.client_id)
raise "PKCE exchange failed" unless http.response.status == 200
pair = JSON.parse(http.response.body)
raise "Token not store scoped" unless OauthAccessToken.authenticate(pair.fetch("access_token"))&.store_id == store.id
exchange.call(code, client.client_id)
raise "Code replay accepted" unless http.response.status == 400
raise "Wrong refresh client accepted" if OauthAccessToken.rotate!(pair.fetch("refresh_token"), client_id: "other")
rotated = OauthAccessToken.rotate!(pair.fetch("refresh_token"), client_id: client.client_id)
raise "Refresh failed" unless rotated
raise "Old access token still valid" if OauthAccessToken.authenticate(pair.fetch("access_token"))
raise "Refresh replay accepted" if OauthAccessToken.rotate!(pair.fetch("refresh_token"), client_id: client.client_id)
http.post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
  headers: { "Authorization" => "Bearer #{rotated.first}", "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }
raise "OAuth token rejected by MCP" unless http.response.status == 200
raise "Products tool missing" unless http.response.body.include?("list_products")

payload = { "data" => { "product" => { "slug" => "gallery-test", "coverUrl" => "https://example.com/cover.jpg",
  "images" => [ { "url" => "https://example.com/cover.jpg", "position" => 0 },
    { "url" => "https://example.com/back.jpg", "position" => 1, "filename" => "back.jpg" } ] } } }
entries = CatalogExecutor.cover_entries(payload)
raise "Gallery association missing" unless entries.size == 2 && entries.last[:slug] == "gallery-test" && entries.last[:label].include?("back.jpg")
parts = CatalogExecutor.response_content(payload, false)
raise "Missing image fallback" unless parts.any? { |part| part[:text].to_s.include?("Image preview unavailable") }
puts "OAuth PKCE, client binding, refresh, MCP auth, gallery association and fallback OK"
