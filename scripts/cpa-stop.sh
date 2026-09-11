#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=cpa-env.sh
source "$ROOT/scripts/cpa-env.sh"

if [[ ! -f "$CPA_PID" ]]; then
  echo "无 pid 文件，不在本脚本托管范围内。"
  exit 0
fi
pid="$(cat "$CPA_PID")"
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid"
  echo "已停 pid=$pid"
else
  echo "pid=$pid 已不在"
fi
rm -f "$CPA_PID"
