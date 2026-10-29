# Filter the complete provider payload before Rails' request instrumentation.
# Provider metadata/custom fields can contain PII outside documented paths.
class StoreOrderWebhookPrivacy
  def initialize(app)
    @app = app
  end

  def call(env)
    if env["PATH_INFO"].to_s.start_with?("/webhooks/store_orders/", "/webhooks/shopify/")
      env["action_dispatch.parameter_filter"] = [ /./ ]
    end
    @app.call(env)
  end
end

Rails.application.config.middleware.insert_before Rails::Rack::Logger, StoreOrderWebhookPrivacy
