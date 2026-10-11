#!/usr/bin/env bash
# Exit on error
set -o errexit
set -o pipefail

bundle install
bundle exec rails assets:precompile
bundle exec rails db:prepare
bundle exec rails morea:online_store:install

# OpenCV recolor lives in this slug. A git deploy does not apply render.yaml,
# so the service has to boot from files this build installs.
root="$(cd "$(dirname "$0")/.." && pwd)"
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

cv2_so="$(find "$root/.venv/lib" -name 'cv2*.so' -print -quit)"
if [ -n "$cv2_so" ] && ldd "$cv2_so" | grep -q "not found"; then
  apt-get update
  apt-get install -y --no-install-recommends libglib2.0-0 libgomp1
fi

"$root/.venv/bin/python" -c "import cv2, fastapi, uvicorn; print('recolor deps', cv2.__version__)"
rm -rf "$UV_CACHE_DIR"
