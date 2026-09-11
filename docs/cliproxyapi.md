# 方案 A · CLIProxyAPI（CPA）

> 场景：**个人自用**，把自己的 Codex / Claude / Gemini 订阅变成 API，喂给 Claude Code 等工具。
> 状态：调研完成，本机已落地安装；OAuth 登录与模型映射待你跑。

---

## 是什么

`router-for-me/CLIProxyAPI`

| 项 | 值 |
|---|---|
| Star | 51229（2026-09-10 `gh api` 实测） |
| 语言 / 协议 | Go / MIT |
| 活跃度 | 当日有提交 |

官方定位（README 逐字）：

> Wrap Antigravity, ChatGPT Codex, Claude Code, Grok Build as an OpenAI/Gemini/Claude/Codex compatible API service, allowing you to enjoy the free Gemini 3.1 Pro, GPT 5.6 Series, Grok 4.5, Claude model through API

**关键：原生输出 Anthropic 格式端点**，Claude Code 直接 `ANTHROPIC_BASE_URL` 指过去就能用，不需要中间再挂协议转换层。

### 为什么选它而不是 sub2api

- 单二进制，不用 PostgreSQL + Redis
- 不需要支付系统、Token 计费、给下游发 key——这些是给别人做生意用的
- 上游就是自己的订阅，没有「分发」画像（官方点名的正是分发行为）

---

## 实现原理

### 链路

```
Claude Code CLI
  │  POST /v1/messages（Anthropic 协议）
  ▼
CLIProxyAPI :8317
  │  ① internal/translator/codex/claude/   协议转换
  │  ② codex-tui 指纹伪装
  │  ③ OAuth token（~/.cli-proxy-api）
  ▼
https://chatgpt.com/backend-api/codex
```

### 三层职责

**① 协议转换** — `internal/translator/codex/claude/`

| Claude Code 发 | 转成 Codex 的 |
|---|---|
| `system` 字段 | `instructions` |
| system message | developer input content |
| 工具声明 | `codex_tool_schema.go` 转换 |
| thinking blocks | reasoning replay 缓存（`codex_reasoning_replay_cache.go`） |

模板见 `codex_claude_request.go:57`：`{"model":"","instructions":"","input":[]}`

**② 客户端伪装** — `codex_executor_request.go`

```go
codexUserAgent = "codex-tui/0.153.3 (Mac OS 26.5.1; arm64) iTerm.app/3.6.11 (codex-tui; 0.153.3)"
codexOriginator = "codex-tui"
```

- 项目内部叫 **cloaking**，开关 `codex.disable-codex-cloaking`（默认 `false`）
- 下游 UA 主动剥掉，避免 Cloudflare 1010
- 随机补 `Session_id`（Mac UA 且无 session header 时）
- 伪造/透传头：`Version`、`X-Codex-Turn-Metadata`、`X-Client-Request-Id`、`X-Codex-Window-Id`、`Thread-Id`、`X-Openai-Internal-Codex-Responses-Lite`、`Chatgpt-Account-Id`

**③ OAuth** — `internal/auth/codex/`

PKCE 流程，token 落 `auth-dir`（默认 `~/.cli-proxy-api`）。支持多账号轮询负载均衡。

---

## 部署骨架

```bash
# 安装（macOS）
brew install cliproxyapi

# 配置目录：/opt/homebrew/etc/cliproxyapi.conf
# 默认端口：8317
```

### 配置要点（`config.example.yaml`，878 行）

顶层键：

| 键 | 说明 |
|---|---|
| `port` | 默认 8317 |
| `auth-dir` | OAuth token 目录，默认 `~/.cli-proxy-api` |
| `api-keys` | **自己签发**的访问口令，不是 OpenAI 的 key |
| `proxy-url` | 出网代理 |
| `routing` | 路由策略 |
| `codex` | Codex 专属配置段（`:241`） |
| `claude-code` | Claude Code 相关段（`:187`） |

### Codex 登录

```bash
cliproxyapi --codex-login
# 无浏览器/远程：--no-browser，手动打开打印的 URL
# 免交互：--codex-device-login
```

OAuth 本地回调端口 **1455**。成功后凭证存到 `auth-dir`。

### 验证

```bash
curl -sS http://127.0.0.1:8317/v1/models \
  -H "Authorization: Bearer <你的 api-keys 值>"
```

---

## 接入 Claude Code

```bash
export ANTHROPIC_BASE_URL=http://127.0.0.1:8317
export ANTHROPIC_AUTH_TOKEN=<你的 api-keys 值>
```

> ⚠️ **不要同时设** `ANTHROPIC_AUTH_TOKEN` 和 `ANTHROPIC_API_KEY`，会触发 Claude Code 的 auth conflict。

或写进 `~/.claude/settings.json`：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8317",
    "ANTHROPIC_AUTH_TOKEN": "<你的 api-keys 值>"
  }
}
```

### 模型映射（三件套，必配）

Claude Code 会调用不同档位的模型，全部要映射，否则后台杂活会拿贵模型刷额度：

```bash
export ANTHROPIC_DEFAULT_HAIKU_MODEL=<便宜快速模型>
export ANTHROPIC_DEFAULT_SONNET_MODEL=<中档模型>
export ANTHROPIC_DEFAULT_OPUS_MODEL=<高档模型>
```

> TODO：具体映射到哪些 Codex 模型 ID 待落地时按 `curl /v1/models` 的真实返回确认。网上流传的 `gpt-5.x-luna` / `-sol` 等名字**未经核实，可能是占位名**。

### 配套开关

```bash
export CLAUDE_CODE_DISABLE_1M_CONTEXT=1              # Codex 后端没有 1M 上下文
export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=3        # 压并发，贴近真人使用
```

**注意**：`CLAUDE_CODE_SUBAGENT_MODEL` 若已设置，会覆盖子代理 frontmatter 里的 `model:`。用前确认 `echo $CLAUDE_CODE_SUBAGENT_MODEL` 为空。

---

## 风险控制

见 [background.md · 个人使用的风险压法](background.md#个人使用的风险压法按杠杆排序)。

方案 A 的天然优势：**单人单账号**，不在官方点名的「多人共享/转售」画像里。

要点：
- 单账号，不拼车
- 压并发
- 映射好小模型
- 网络稳定
- **别关 cloaking**

---

## 已知坑

| 坑 | 说明 |
|---|---|
| 工具调用与计费冲突 | 只在「CPA 外面再套 new-api」时出现。**别套** |
| VSCode 插件缓存异常 | VSCode 里 Claude Code 插件的 native 视图缓存按模型固定读取会出错；用 CLI / 终端视图 / IDEA 插件正常 |
| 远程部署 OAuth 回调 | `localhost:1455` 在服务器上打不开，用 `--no-browser` 手动提交回调 URL 或 `--codex-device-login` |
| 配置不支持环境变量 | CPA 配置只接受字面值，真实密钥别提交进 git |

---

## 本机落地（2026-09-10）

- 安装：`brew install cliproxyapi` → **7.2.155**
- 配置：`~/.cli-proxy-api/config.yaml`，`host: 127.0.0.1`，`port: 8317`，`codex.disable-codex-cloaking: false`
- Homebrew 默认路径 `/opt/homebrew/etc/cliproxyapi.conf` 已 symlink 到上面那份
- 仓库：`config.example.yaml` + `scripts/cpa-{start,stop,login,status}.sh`
- **不要** `brew services start`（会开机自启）。用脚本起停。
- cc-switch Claude provider：`cpa-codex` → `http://127.0.0.1:8317`（`ANTHROPIC_AUTH_TOKEN`）。**未** `provider switch`，current 仍是 qax。
- 临时用：`cc-switch start claude cpa-codex`（先 `cpa-start.sh` + 已 login）
- 建议附加（GUI 里补，或 start 时自己 export）：`CLAUDE_CODE_DISABLE_1M_CONTEXT=1`、`CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=3`
- 冒烟：未 login 时 `GET /v1/models` HTTP 200、模型列表空

下一步：`./scripts/cpa-login.sh` → 再 `cpa-start` → `cpa-status` 看真实模型 ID → 填 Haiku/Sonnet/Opus 映射。

## 待补

- [x] 完整 `config.yaml` 样例（仓库 `config.example.yaml`；本机真配置不入库）
- [ ] 实测：`curl /v1/models` 的真实模型列表（需 Codex OAuth）
- [ ] 实测：Claude Code 走通后的额度消耗速率
- [x] 与本地 cc-switch 的接入方式（provider `cpa-codex`，临时 start，不切全局）
- [ ] 远程/服务器部署形态
