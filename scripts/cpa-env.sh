#!/usr/bin/env bash
# 给其它脚本 source。密钥只从本机文件读，不回显全文。
# 二进制优先用 sources/ 编译产物，没有才回退 brew。
set -euo pipefail

_CPA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CPA_CONFIG="${CPA_CONFIG:-$HOME/.cli-proxy-api/config.yaml}"
CPA_LOG="${CPA_LOG:-$HOME/.cli-proxy-api/cliproxyapi.log}"
CPA_PID="${CPA_PID:-$HOME/.cli-proxy-api/cliproxyapi.pid}"

if [[ -z "${CPA_BIN:-}" ]]; then
  if SRC_BIN="$("$_CPA_ROOT/scripts/repo.sh" bin cliproxyapi 2>/dev/null)"; then
    CPA_BIN="$SRC_BIN"
    CPA_BIN_FROM=source
  elif [[ -x /opt/homebrew/bin/cliproxyapi ]]; then
    CPA_BIN=/opt/homebrew/bin/cliproxyapi
    CPA_BIN_FROM=brew
  else
    CPA_BIN=""
    CPA_BIN_FROM=missing
  fi
else
  CPA_BIN_FROM=env
fi

cpa_api_key() {
  python3 - "$CPA_CONFIG" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
in_keys = False
for line in text.splitlines():
    if line.startswith("api-keys:"):
        in_keys = True
        continue
    if in_keys:
        s = line.strip()
        if s.startswith("- "):
            print(s[2:].strip().strip('"').strip("'"))
            raise SystemExit(0)
        if s and not s.startswith("#") and not s.startswith("-"):
            break
raise SystemExit("no api-keys in config")
PY
}

cpa_port() {
  python3 - "$CPA_CONFIG" <<'PY'
from pathlib import Path
import sys
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.startswith("port:"):
        print(line.split(":", 1)[1].strip())
        raise SystemExit(0)
print("8317")
PY
}
