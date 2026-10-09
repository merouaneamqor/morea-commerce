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

- Local storefront: http://morea.lvh.me:3010 (or http://localhost:3010)
- Production base domain: **ollazen.com** (tenants at `{slug}.ollazen.com`, e.g. https://morea.ollazen.com)
- Store admin: `/admin` — store staff land on the COD **Home**
- Platform (super admin): `admin@morea.website` / `morea123` — lands on **/admin/platform**. Use **Open admin** on a tenant for store ops, then **Platform** to return.
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

Then open http://atelier.lvh.me:3010 (local) or https://atelier.ollazen.com (prod — add that hostname as a Custom Domain on the Render `morea` service; Free plan needs one domain per store, DNS `*.ollazen.com` is already set).

`APP_BASE_DOMAIN=ollazen.com` in production. Locally docker-compose uses `lvh.me`.

## Stack

Rails 8 · Hotwire · Tailwind · PostgreSQL · Redis · Sidekiq
