#!/usr/bin/env bash
# 上游源码仓库接口：按 repos/<id>.json clone / 更新 / 编译。
# GitHub 走 gh；git 层关掉死掉的 github.com 代理，避免 7897 不通时 clone 挂死。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="${1:-}"
ID="${2:-}"

usage() {
  echo "usage: $0 <sync|build|path|bin|list> [id]" >&2
  echo "  sync   clone 或 fetch 到 repos/<id>.path" >&2
  echo "  build  在 checkout 里执行 repos/<id>.build.command" >&2
  echo "  path   打印本地源码目录" >&2
  echo "  bin    打印编译产物路径（不存在则非 0）" >&2
  echo "  list   列出 repos/*.json" >&2
  exit 2
}

[[ -n "$CMD" ]] || usage
if [[ "$CMD" != "list" && -z "$ID" ]]; then
  usage
fi

git_github() {
  git -c "http.https://github.com/.proxy=" "$@"
}

load_spec() {
  local spec="$ROOT/repos/${ID}.json"
  if [[ ! -f "$spec" ]]; then
    echo "没有仓库接口: $spec" >&2
    echo "现有:" >&2
    ls "$ROOT/repos"/*.json 2>/dev/null | xargs -n1 basename | sed 's/\.json$//' >&2 || true
    exit 1
  fi
  python3 - "$spec" "$ROOT" <<'PY'
import json, os, sys
spec_path, root = sys.argv[1], sys.argv[2]
d = json.load(open(spec_path))
path = d["path"]
if not os.path.isabs(path):
    path = os.path.join(root, path)
print(d["github"])
print(d.get("ref") or "main")
print(path)
print(d.get("bin") or "")
print(" ".join(d.get("build", {}).get("command") or []))
PY
}

read_spec() {
  local github ref path bin build
  github=$(load_spec | sed -n '1p')
  ref=$(load_spec | sed -n '2p')
  path=$(load_spec | sed -n '3p')
  bin=$(load_spec | sed -n '4p')
  build=$(load_spec | sed -n '5p')
  SPEC_GITHUB="$github"
  SPEC_REF="$ref"
  SPEC_PATH="$path"
  SPEC_BIN="$bin"
  SPEC_BUILD="$build"
}

# load_spec 调了 5 次 python，改成一次
read_spec_once() {
  eval "$(python3 - "$ROOT/repos/${ID}.json" "$ROOT" <<'PY'
import json, os, shlex, sys
d = json.load(open(sys.argv[1]))
root = sys.argv[2]
path = d["path"]
if not os.path.isabs(path):
    path = os.path.join(root, path)
binrel = d.get("bin") or ""
build = d.get("build", {}).get("command") or []
print("SPEC_GITHUB=" + shlex.quote(d["github"]))
print("SPEC_REF=" + shlex.quote(d.get("ref") or "main"))
print("SPEC_PATH=" + shlex.quote(path))
print("SPEC_BINREL=" + shlex.quote(binrel))
print("SPEC_BIN=" + shlex.quote(os.path.join(path, binrel) if binrel else ""))
print("SPEC_BUILD=" + " ".join(shlex.quote(x) for x in build))
PY
)"
}

cmd_list() {
  python3 - "$ROOT/repos" <<'PY'
from pathlib import Path
import json, sys
root = Path(sys.argv[1])
for p in sorted(root.glob("*.json")):
    d = json.loads(p.read_text())
    print(f"{d.get('id', p.stem):16}  {d.get('github','')}  →  {d.get('path','')}")
PY
}

cmd_sync() {
  read_spec_once
  mkdir -p "$(dirname "$SPEC_PATH")"
  if [[ ! -d "$SPEC_PATH/.git" ]]; then
    echo "clone $SPEC_GITHUB → $SPEC_PATH"
    git_github clone "https://github.com/${SPEC_GITHUB}.git" "$SPEC_PATH"
  fi
  git_github -C "$SPEC_PATH" fetch origin
  git_github -C "$SPEC_PATH" checkout "$SPEC_REF"
  git_github -C "$SPEC_PATH" pull --ff-only origin "$SPEC_REF" || true
  echo "ok $(git -C "$SPEC_PATH" rev-parse --short HEAD) $SPEC_PATH"
}

cmd_build() {
  read_spec_once
  if [[ ! -d "$SPEC_PATH/.git" ]]; then
    echo "源码不在，先: $0 sync $ID" >&2
    exit 1
  fi
  if [[ -z "$SPEC_BUILD" ]]; then
    echo "repos/${ID}.json 没有 build.command" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$SPEC_BIN")"
  echo "build in $SPEC_PATH: $SPEC_BUILD"
  (
    cd "$SPEC_PATH"
    export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"
    export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
    eval "$SPEC_BUILD"
  )
  if [[ -n "$SPEC_BIN" && ! -x "$SPEC_BIN" ]]; then
    echo "编译结束但找不到可执行文件: $SPEC_BIN" >&2
    exit 1
  fi
  echo "bin $SPEC_BIN"
}

cmd_path() {
  read_spec_once
  echo "$SPEC_PATH"
}

cmd_bin() {
  read_spec_once
  if [[ -z "$SPEC_BIN" || ! -x "$SPEC_BIN" ]]; then
    exit 1
  fi
  echo "$SPEC_BIN"
}

case "$CMD" in
  list) cmd_list ;;
  sync) cmd_sync ;;
  build) cmd_build ;;
  path) cmd_path ;;
  bin) cmd_bin ;;
  *) usage ;;
esac
