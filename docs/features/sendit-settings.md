# Sendit settings in Integrations

Integrations → Delivery companies → Sendit settings contains the pickup city, parcel opening/try-on options, webhook configuration, fallback shipping fee and free-shipping threshold. General Settings links here and keeps its unrelated settings. API keys continue through the existing verified Sendit connection dialog and remain encrypted for managed delivery accounts.

The form updates only the authorized workspace's delivery options. Leaving the webhook secret blank preserves its saved value. Managed connections show their authenticated webhook URL; older standalone configurations retain their signed webhook secret controls. Existing pickup IDs remain selected if city data has expired from the cache.

Opening Integrations only reads cached Sendit city lists and rates. Refresh cities explicitly queues the existing refresh job; page navigation never authenticates with or fetches data from the provider.

Managed connections retain their Delete button. Removing the final active credential-bearing Sendit account clears older fallback credentials and webhook configuration, preventing the deleted connection from silently reconnecting. Deleting an inactive historical row preserves a live older connection. Workspaces using older standalone credentials can delete that connection from Sendit settings. Token and city caches are invalidated; orders and delivery history are preserved.

Verification uses synthetic workspaces and mocked provider requests:

```sh
RAILS_ENV=test bundle exec rspec spec/requests/sendit_settings_spec.rb spec/requests/sendit_connection_spec.rb spec/requests/seller_integrations_spec.rb
```
