# Hosting follow-ups (Render)

In-app speed work lives in the speed-kit PR. These items need the Render service
or an edge CDN and are not verified from this repository alone.

## Brotli

`Rack::Deflater` adds gzip for HTML/JSON/CSS/JS when the client accepts it.
Brotli needs Thruster (already in the Gemfile) or the Render/proxy edge.

Option A, wrap Puma with Thruster in `bin/render-start.sh`:

```bash
exec bundle exec thrust bin/rails server -b 0.0.0.0 -p "$PORT"
```

(Keep Sidekiq started beside it the way the free plan already does.)

Option B, enable compression on a CDN in front of `seallo.ma` and leave origin gzip as a fallback.

## CDN for static assets

Production already sets far-future `Cache-Control` on digested public assets.
To offload bytes from the web dyno, set `ASSET_HOST` to a CDN origin that
mirrors `/assets/*` (Cloudflare, Fastly, or Render static). Digested Propshaft
URLs stay cacheable for a year.

Cloudinary already delivers storefront product images with `f_auto,q_auto`
(WebP/AVIF when the client supports them).

## Co-location and load balancing

`render.yaml` places the web service in `frankfurt`. Keep Postgres and Redis in
the same region. Horizontal load balancing needs a paid plan with `WEB_CONCURRENCY`
greater than 0 and a pool sized for Puma threads; the free 512Mi co-hosts Sidekiq
and intentionally keeps a single Puma process.

## OpenTelemetry

Not enabled here. A later slice can add `opentelemetry-sdk` plus an exporter
when a collector endpoint exists. Prefer sampling slow Active Record queries
only; full traces on the free plan will fight memory limits.
