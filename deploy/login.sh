#!/usr/bin/env bash
set -euo pipefail

SERVICE_USER="${CPA_SERVICE_USER:-cliproxyapi}"
CONF_DIR="${CPA_CONF_DIR:-/etc/ai-sub-gateway}"
BIN_PATH="${CPA_BIN_PATH:-/usr/local/bin/cliproxyapi}"
[[ "$(id -u)" -eq 0 ]] || { echo "run as root: sudo bash deploy/login.sh" >&2; exit 1; }
[[ -x "$BIN_PATH" ]] || { echo "missing $BIN_PATH; run deploy/install.sh first" >&2; exit 1; }
echo "Copy the printed OAuth URL to a browser on your local computer if needed."
exec sudo -u "$SERVICE_USER" "$BIN_PATH" -config "$CONF_DIR/config.yaml" -codex-login --no-browser "$@"
