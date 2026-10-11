#!/usr/bin/env bash
# Exit on error
set -o errexit
set -o pipefail

bundle install
bundle exec rails assets:precompile
bundle exec rails db:prepare
bundle exec rails morea:online_store:install

# OpenCV recolor is part of this service. Install it into the slug so
# bin/render-start.sh can serve http://127.0.0.1:8000.
root="$(cd "$(dirname "$0")/.." && pwd)"

install_with_uv() {
  export UV_INSTALL_DIR="$root/.uv"
  export UV_PYTHON_INSTALL_DIR="$root/.uv/python"
  export UV_CACHE_DIR="${TMPDIR:-/tmp}/uv-cache"
  export UV_NO_MODIFY_PATH=1
  export PATH="$UV_INSTALL_DIR:$PATH"

  if [ ! -x "$UV_INSTALL_DIR/uv" ]; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi

  "$UV_INSTALL_DIR/uv" python install 3.12
  "$UV_INSTALL_DIR/uv" venv "$root/.venv" --python 3.12
  "$UV_INSTALL_DIR/uv" pip install --python "$root/.venv/bin/python" -r "$root/services/recolor/requirements.txt"
  rm -rf "$UV_CACHE_DIR"
}

if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)'; then
  if python3 -m venv "$root/.venv" && "$root/.venv/bin/python" -m pip install -r "$root/services/recolor/requirements.txt"; then
    echo "recolor: installed with system python3"
  else
    echo "recolor: system python venv failed, installing with uv" >&2
    rm -rf "$root/.venv"
    install_with_uv
  fi
else
  echo "recolor: installing Python with uv"
  install_with_uv
fi

cv2_so="$(find "$root/.venv/lib" -name 'cv2*.so' -print -quit || true)"
if [ -n "$cv2_so" ] && command -v ldd >/dev/null 2>&1 && ldd "$cv2_so" | grep -q "not found"; then
  apt-get update && apt-get install -y --no-install-recommends libglib2.0-0 libgomp1 || true
fi

"$root/.venv/bin/python" -c "import cv2, fastapi, uvicorn; print('recolor deps', cv2.__version__)"
