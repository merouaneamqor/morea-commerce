# Morea Commerce

Luxury modest sportswear storefront + COD admin for Morocco.

**Storefront:** fashion-house UX (campaign homepage, editorial PDP, restrained blush).  
**Admin:** dense and operational — not luxurious.

## Run

```bash
docker compose up --build
```

- Storefront: http://localhost:3010
- Admin: http://localhost:3010/admin — `admin@morea.website` / `morea123`

```bash
docker compose exec web bin/rails db:migrate db:seed
```

## Stack

Rails 8 · Hotwire · Tailwind · PostgreSQL · Redis · Sidekiq
