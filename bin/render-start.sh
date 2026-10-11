#!/usr/bin/env bash
set -o errexit

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# Listen on loopback and export RECOLOR_SERVICE_URL for Puma. Render dashboard
# env vars are unchanged until a blueprint sync; this is what the web process uses.
start_local_recolor() {
  case "${RECOLOR_SERVICE_URL:-}" in
    ""|http://127.0.0.1:*|http://localhost:*|https://127.0.0.1:*|https://localhost:*)
      ;;
    *)
      echo "recolor: using RECOLOR_SERVICE_URL"
      return 0
      ;;
  esac

  if [ ! -x "$root/.venv/bin/python" ]; then
    echo "recolor: project Python is missing; colorways cannot run" >&2
    return 0
  fi

  export OMP_NUM_THREADS=1
  export OPENBLAS_NUM_THREADS=1
  export MKL_NUM_THREADS=1
  export RECOLOR_MAX_EDGE="${RECOLOR_MAX_EDGE:-1000}"

  "$root/.venv/bin/python" -m uvicorn app.main:app \
    --app-dir "$root/services/recolor" \
    --host 127.0.0.1 \
    --port 8000 \
    --log-level info &

  local i
  for i in $(seq 1 60); do
    if "$root/.venv/bin/python" -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=1).read()" >/dev/null 2>&1; then
      export RECOLOR_SERVICE_URL="http://127.0.0.1:8000"
      echo "recolor: RECOLOR_SERVICE_URL=http://127.0.0.1:8000"
      return 0
    fi
    sleep 0.5
  done

  echo "recolor: health check failed" >&2
}

start_local_recolor

# Seed once on empty catalog, then boot Sidekiq + Puma together (single Render web service).
bundle exec rails runner 'load "db/seeds.rb" if defined?(Store) && Store.count.zero?'

bundle exec sidekiq -C config/sidekiq.yml &
exec bundle exec puma -C config/puma.rb
