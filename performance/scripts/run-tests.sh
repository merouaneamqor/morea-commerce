#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Refuse invocation with custom CLI overrides. Profiles define hard traffic limits.
profile="${1:-smoke}"
[[ $# -le 1 ]] || { echo 'Usage: run-tests.sh PROFILE' >&2; exit 2; }
case "$profile" in
  smoke|baseline|checkout|spike) script="$profile" ;;
  moderate|high|stress|extreme) script=stress ;;
  *) echo "Unknown profile: $profile" >&2; exit 2 ;;
esac

# Ambient K6_* options can override script limits; only permit the binary path.
if compgen -e | grep '^K6_' > /dev/null; then
  echo 'Unset ambient K6_* variables before running these profiles.' >&2
  exit 2
fi
mkdir -p results
export PERF_PROFILE="$profile"
exec k6 run --config ./k6/defaults.json --summary-export "results/$profile.json" "k6/$script.js"
