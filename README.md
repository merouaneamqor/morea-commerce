# Morea Commerce

Luxury modest sportswear storefront + COD admin for Morocco.

**Storefront:** fashion-house UX (campaign homepage, editorial PDP, restrained blush).  
**Store admin:** dense and operational — not luxurious.  
**Platform:** SaaS owner home for super admins (all tenants).

Stores are subdomain tenants. Each store has its own catalog, staff, orders, and Sendit/Discord credentials.

## Run

```bash
docker compose up --build
```

- Storefront: http://morea.lvh.me:3010 (or http://localhost:3010)
- Store admin: http://localhost:3010/admin — store staff land on the COD **Home**
- Platform (super admin): same login with `admin@morea.website` / `morea123` — lands on **/admin/platform** (stores + SaaS metrics). Use **Open admin** on a tenant for store ops, then **Platform** to return.
- Platform-only account: `super@morea.website` / `morea123`

```bash
docker compose exec web bin/rails db:migrate db:seed
```

### Create another tenant

From the platform UI (**New store**), or:

```bash
docker compose exec web env \
  TENANT_SLUG=atelier TENANT_NAME=Atelier \
  ADMIN_EMAIL=admin@atelier.test ADMIN_PASSWORD=secret \
  bin/rails tenants:create
```

Then open http://atelier.lvh.me:3010

Set `APP_BASE_DOMAIN` (and `APP_PORT` locally) so Discord links and webhooks use the right host. In production, point a wildcard DNS record at the app (`*.example.com`).

## Stack

Rails 8 · Hotwire · Tailwind · PostgreSQL · Redis · Sidekiq
