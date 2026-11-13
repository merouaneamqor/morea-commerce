# Third-party SDK inventory

Living inventory of outbound scripts and services that can touch storefront or platform data. Update when adding a vendor.

| Vendor | Surface | Loads when | Data notes |
|---|---|---|---|
| Meta Pixel (`connect.facebook.net`) | Tenant storefront | Pixel ID set **and** tracking consent granted | PageView / ecommerce events |
| TikTok Pixel (`analytics.tiktok.com`) | Tenant storefront | Pixel ID set **and** tracking consent granted | Page / ecommerce events |
| Google Fonts | Storefront / admin / auth | Always (layout) | Font CSS only; consider self-host later |
| Unsplash images | Optional media URLs | Merchant-configured URLs | CDN image fetch |
| Sendit | Admin + checkout shipping | Keys configured | Delivery addresses for parcels |
| Shopify / Seallo | Connected stores | OAuth connection | Orders + privacy webhooks |
| WooCommerce / YouCan | Connected stores | Connection configured | Order import |
| Meta Ads Graph API | Admin ads | OAuth connection | Ad accounts; deletion callback at `/auth/meta/data-deletion` |
| Discord webhooks | Admin notifications | Webhook URL set | Order summaries |
| Chart.js | Admin dashboards | Vendor license MIT | No customer PII |

Cookie notice copy and [checklist-20.md](checklist-20.md) should stay aligned with this table.
