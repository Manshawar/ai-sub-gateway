#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=cpa-env.sh
source "$ROOT/scripts/cpa-env.sh"

port="$(cpa_port)"
echo "config: $CPA_CONFIG"
echo "bin:    $CPA_BIN ($CPA_BIN_FROM) ($("$CPA_BIN" -h 2>&1 | head -1))"
if [[ -f "$CPA_PID" ]] && kill -0 "$(cat "$CPA_PID")" 2>/dev/null; then
  echo "proc:   running pid=$(cat "$CPA_PID")"
else
  echo "proc:   stopped"
fi
lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | sed 's/^/listen: /' || echo "listen: none on $port"

auth_n="$(find "$HOME/.cli-proxy-api" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
echo "oauth:  $auth_n json under ~/.cli-proxy-api"

key="$(cpa_api_key)"
echo "key:    ${key:0:8}… len=${#key}"
code="$(curl -sS -o /tmp/cpa-models.json -w '%{http_code}' \
  -H "Authorization: Bearer $key" \
  "http://127.0.0.1:${port}/v1/models" || true)"
echo "GET /v1/models → HTTP $code"
if [[ -f /tmp/cpa-models.json ]]; then
  python3 - <<'PY'
import json
from pathlib import Path
p = Path("/tmp/cpa-models.json")
raw = p.read_text().strip()
if not raw:
    raise SystemExit
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print(raw[:300])
    raise SystemExit
ids = [m.get("id") for m in data.get("data", [])][:20]
print("models:", ", ".join(ids) if ids else "(empty — 多半还没 --codex-login)")
PY
fi
