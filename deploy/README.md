# Linux deployment

For one personal Codex subscription, run on the Linux server:

```bash
sudo bash deploy/install.sh
sudo bash deploy/login.sh
```

The installer creates a dedicated `cliproxyapi` system user, stores OAuth data
in `/var/lib/ai-sub-gateway/auth`, and runs one hardened systemd service. The
API binds to `127.0.0.1:8317` by default, suitable when Clawbot is on the same
server.

Clawbot provider settings:

- Base URL: `http://127.0.0.1:8317/v1`
- API key: `CPA_API_KEY` from `/etc/ai-sub-gateway/gateway.env`
- Model: `gpt-5.6-luna`

For a Clash/Mihomo outbound proxy, pass its local HTTP port during installation:

```bash
sudo CPA_PROXY_URL=http://127.0.0.1:7897 bash deploy/install.sh
```

If Clawbot is on another machine, use a private WireGuard/Tailscale network or
an authenticated TLS reverse proxy. Do not expose port 8317 directly to the
Internet. The upstream installer is used for the CLIProxyAPI binary; set
`CPA_INSTALLER_URL` or preinstall `/usr/local/bin/cliproxyapi` to pin/replace it.
