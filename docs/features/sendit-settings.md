# Sendit settings

Sendit runtime options live on a dedicated settings page (`/admin/sendit_settings`): pickup city, parcel opening/try-on options, webhook configuration, fallback shipping fee and free-shipping threshold. The Integrations page only shows connection status and a Settings link. General Settings links here and keeps its unrelated settings. API keys continue through the verified Sendit connection dialog on Integrations and remain encrypted for managed delivery accounts.

The form updates only the authorized workspace's delivery options. Leaving the webhook secret blank preserves its saved value. Managed connections show their authenticated webhook URL; older standalone configurations retain their signed webhook secret controls. Existing pickup IDs remain selected if city data has expired from the cache.

Opening Sendit settings only reads cached city lists and rates. Refresh cities explicitly queues the existing refresh job; page navigation never authenticates with or fetches data from the provider.

Managed connections retain their Delete button on Integrations. Removing the final active credential-bearing Sendit account clears older fallback credentials and webhook configuration, preventing the deleted connection from silently reconnecting. Deleting an inactive historical row preserves a live older connection. Workspaces using older standalone credentials can delete that connection from Sendit settings. Token and city caches are invalidated; orders and delivery history are preserved.

Ozon Express and Ameex follow the same pattern: Integrations shows status, and `/admin/ozon_settings` or `/admin/ameex_settings` hold parcel options for the connected account.

Verification uses synthetic workspaces and mocked provider requests:

```sh
RAILS_ENV=test bundle exec rspec spec/requests/sendit_settings_spec.rb spec/requests/ozon_settings_spec.rb spec/requests/ameex_settings_spec.rb spec/requests/sendit_connection_spec.rb spec/requests/seller_integrations_spec.rb
```
