# Meta Ads connection and spend sync

Merchants connect a Meta (Facebook) login, link ad accounts to their workspace, and seallo reads daily ad spend so profit can include it. Read-only: only `ads_read` and `business_management` are requested. Ad controls (pause, budget, duplicate) are a later batch with their own review.

## Environment

| Variable | Required | What it is |
| --- | --- | --- |
| `META_APP_ID` | yes | App ID of the Meta app. |
| `META_APP_SECRET` | yes | App secret. Server only; never sent to the browser or logged. |
| `META_LOGIN_CONFIG_ID` | yes | ID of the Facebook Login for Business configuration (its permissions are `ads_read` and `business_management`). |
| `META_REDIRECT_URI` | yes | The one redirect URI, on the platform apex: `https://<APP_BASE_DOMAIN>/auth/meta/callback`. Must match the Meta app's "Valid OAuth Redirect URIs" exactly. |
| `META_GRAPH_VERSION` | no | Graph API version, default `v25.0`. (`META_GRAPH_API_VERSION` is still read as an alias.) |
| `META_ADS_SYNC_CRON` | no | Cron of the sync job, default `5 * * * *` (hourly). |
| `META_ADS_EXTERNAL_CRON` | no | Set when an external runner calls `MetaAdsSyncJob` instead of sidekiq-cron. |

Without the four required variables the Connect button is disabled and the page says Meta is not configured.

## Meta app settings

- Facebook Login for Business > Configuration: permissions `ads_read` and `business_management`, access token type "User access token".
- Valid OAuth Redirect URIs: the value of `META_REDIRECT_URI`.
- App settings > Advanced (or Data Deletion): **Data deletion request URL** `https://<APP_BASE_DOMAIN>/auth/meta/data-deletion` (callback, not instructions).
- Privacy policy URL: a page that says what is read (ad accounts, campaign/ad names, spend and results), why, and how to delete it.

## Flow

1. Integrations page > Publicité > **Connecter Meta** (POST `/admin/meta-ads/connect`) redirects to `https://www.facebook.com/<version>/dialog/oauth` with `config_id`, `redirect_uri`, `response_type=code` and a signed `state`.
2. `state` is a signed, expiring token (10 minutes) naming the store and user, plus a random nonce kept in the session and as a SHA-256 digest on the connection. The callback accepts it once, and only if signature, expiry, session, user, store and digest all agree.
3. Meta redirects to `/auth/meta/callback` on the apex. The code is exchanged for a short-lived token, then a long-lived one (`fb_exchange_token`), and `debug_token` gives the user id, granted scopes and expiry. The token is stored encrypted (AES-256-GCM) and never rendered, logged or sent to the browser.
4. The merchant is sent back to `<store>.<domain>/admin/meta-ads`. Cancelling or denying shows a clear message and stores nothing. `ads_read` is required; without `business_management` only the profile's own ad accounts are visible, which the page says.
5. `GET /me/adaccounts?fields=id,name,currency,account_status,timezone_name` lists the accounts. Only status 1 (active) and 9 (grace period) can be linked; disabled, unsettled, under review or closed accounts are shown but not selectable. One Meta ad account is linked to one workspace at a time.

## Spend sync (`MetaAdsSyncJob`, hourly)

- First run: the last 30 days. After that: yesterday and today (Meta revises recent numbers). Days follow the ad account's own timezone.
- `GET act_<id>/insights?level=campaign|ad&time_increment=1`, with names and ids for campaign, ad set and ad, spend, impressions, reach, clicks, ctr, cpc, cpm, actions and action values.
- Rows are upserted by (ad account, campaign, day) and (ad account, ad, day): a re-sync never duplicates. Campaign rows and ad rows are two views of the same spend; never add one to the other.
- Purchases: one of `omni_purchase`, `purchase`, `offsite_conversion.fb_pixel_purchase` (first present), so one purchase is not counted three times. These are Meta-attributed figures, not seallo orders.
- Currency: `spend` and `currency` are the ad account's. `spend_display` = `spend` x `fx_rate`, in the store's currency, with `fx_rate` and `fx_date` (the date of the rate used). Rates come from open.er-api.com, which publishes the latest rate only, so older days use the closest rate on record and say so in `fx_date`. If no rate can be had, `spend_display` stays empty and is filled on the next sync; nothing is converted with an invented rate.
- Rate limits: usage headers (`x-app-usage`, `x-business-use-case-usage`, `x-ad-account-usage`) are read. Above 75% the next run is pushed back 15 minutes. On a rate limit or a Meta/network failure the account backs off 1, 2, 4, ... minutes (cap 1 hour), or as long as Meta asks, then recovers by itself.

## Token lifecycle

- 7 days before `token_expires_at`, every workspace page shows a warning with a Reconnect button.
- Error 190 (invalid or expired token) or a removed permission marks the connection **needs reconnect**, stops syncing every linked account, and shows a banner. Synced history is kept.
- **Disconnect** asks Meta to revoke the permissions (`DELETE /me/permissions`), deletes the token and unlinks the accounts. If Meta cannot be reached the local disconnect still happens. Spend history is kept.

## Data deletion callback

`POST /auth/meta/data-deletion` with Meta's `signed_request`: verified with HMAC-SHA256 and the app secret (bad or missing signatures get 400 and change nothing), then every connection of that Meta user, in every store, loses its token, user id and linked accounts. The answer is `{ "url": ".../auth/meta/data-deletion/<code>", "confirmation_code": "<code>" }`. The status page shows the code and `completed`. The Meta user id is kept only as a SHA-256 digest. Synced spend stays with the merchant's records.

## Ads to products

Ads are linked to products so a product's profit includes its ad spend: automatically when an ad, ad set or campaign name contains exactly one product's SKU or name (a name that fits two products, or half a word, is left alone), or by hand on the Meta Ads page (a manual link replaces an automatic one). `MetaAds::ProductSpend.call(store:, range:)` returns spend per product in the store's currency: each ad row goes to the product linked to its ad, else its ad set, else its campaign; spend with no link is reported as `unassigned`, and rows still without a conversion are counted, not added.

```
product profit = sales - product cost - delivery fees - ProductSpend.by_product[product_id]
```

## App Review (ads_read, business_management)

Screencast, 2 to 3 minutes, one take, English UI or subtitled, real test merchant account:

1. Show the Meta app's Facebook Login for Business configuration with only `ads_read` and `business_management`.
2. Log in to seallo as a merchant. Open Integrations API > Publicité and click **Connecter Meta**.
3. Show the Facebook dialog listing the two permissions and accept. Show the redirect back to seallo.
4. On the Meta Ads page, show the ad accounts with currency, status and timezone; show an unsettled/disabled account is not selectable; link one account.
5. Wait for (or trigger) the first sync and show daily spend by campaign and by ad for the account (use the dev status page or the profit view), with the converted amount and the rate date.
6. Show the ads-to-products screen and a product with its ad spend.
7. Click **Déconnecter**, then show that Meta's "Apps and Websites" no longer lists the app (permissions revoked).
8. Say what each permission is used for: `ads_read` reads spend and results of the ad accounts the merchant links, to compute real cost per delivered order; `business_management` lists the ad accounts owned by the merchant's Business portfolio.

`ads_management` (pause, budget, duplicate) is not requested here. It belongs to the next batch, with its own screencast: show each action's confirmation dialog (old to new budget in the account currency), the history log, and the role check.
