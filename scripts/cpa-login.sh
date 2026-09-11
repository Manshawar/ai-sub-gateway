#!/usr/bin/env bash
# 浏览器走 ChatGPT OAuth。回调默认 localhost:1455。
# Clash/代理没开时 chatgpt.com 可能打不开。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=cpa-env.sh
source "$ROOT/scripts/cpa-env.sh"

exec "$CPA_BIN" -config "$CPA_CONFIG" -codex-login "$@"
