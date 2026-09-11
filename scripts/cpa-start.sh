#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=cpa-env.sh
source "$ROOT/scripts/cpa-env.sh"

if [[ ! -x "${CPA_BIN:-}" ]]; then
  echo "cliproxyapi 未编译。先: $ROOT/scripts/repo.sh sync cliproxyapi && $ROOT/scripts/repo.sh build cliproxyapi" >&2
  exit 1
fi
echo "bin: $CPA_BIN  ($CPA_BIN_FROM)"
if [[ ! -f "$CPA_CONFIG" ]]; then
  echo "缺少配置: $CPA_CONFIG" >&2
  exit 1
fi

if [[ -f "$CPA_PID" ]] && kill -0 "$(cat "$CPA_PID")" 2>/dev/null; then
  echo "已在跑 pid=$(cat "$CPA_PID")  log=$CPA_LOG"
  exit 0
fi

port="$(cpa_port)"
if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "端口 $port 已被占用，未启动。换端口改 $CPA_CONFIG 的 port 后再跑本脚本。" >&2
  lsof -nP -iTCP:"$port" -sTCP:LISTEN
  exit 1
fi

mkdir -p "$(dirname "$CPA_LOG")"
nohup "$CPA_BIN" -config "$CPA_CONFIG" >>"$CPA_LOG" 2>&1 &
echo $! >"$CPA_PID"
echo "已启动 pid=$(cat "$CPA_PID")  http://127.0.0.1:$port"
echo "日志: tail -f $CPA_LOG"
