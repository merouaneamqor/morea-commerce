# Morea Commerce

Luxury modest sportswear storefront + COD admin for Morocco.

**Storefront:** fashion-house UX (campaign homepage, editorial PDP, restrained blush).  
**Admin:** dense and operational — not luxurious.

Stores are subdomain tenants. Each store has its own catalog, staff, orders, and Sendit/Discord credentials.

## Run

```bash
docker compose up --build
```

- Storefront: http://morea.lvh.me:3010
- Admin: http://morea.lvh.me:3010/admin — `admin@morea.website` / `morea123`

```bash
docker compose exec web bin/rails db:migrate db:seed
```

### Create another tenant

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
