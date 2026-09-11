# ai-sub-gateway

把 **AI 产品订阅额度**转成 **API** 的方案集与落地配置。

解决的核心问题：手上有 ChatGPT/Codex、Claude、Gemini 等**订阅**（不是 API key），怎么在 Claude Code、Codex CLI、各种 AI 工具里把这份额度用起来。

---

## 两个方案

| | 方案 A · CLIProxyAPI | 方案 B · sub2api |
|---|---|---|
| 场景 | **个人自用**，单账号 | **多人拼车**，分摊高额度 |
| 原料 | 自己的订阅账号（OAuth） | 多人/多账号订阅池 |
| 形态 | 单二进制，本机跑 | 平台级，PostgreSQL + Redis + Docker |
| 分发 | 自己用，一个 key 搞定 | 给下游发 key、按量计费、有支付系统 |
| 风险 | 中（单人自用，官方未点名） | **高（官方点名过）** |
| 文档 | [docs/cliproxyapi.md](docs/cliproxyapi.md) | [docs/sub2api.md](docs/sub2api.md) |

**背景知识**（生态谱系、上游机制、封号原理）见 [docs/background.md](docs/background.md)。

---

## 快速定位

- 只想**自己**在 Claude Code 里用 Codex 订阅 → 方案 A
- 要**和朋友分摊**一份高额度订阅 → 方案 B，但先读完 [风险那一节](docs/sub2api.md#风险-必读)
- 搞不清 one-api / new-api / CPA / sub2api 谁是谁 → [docs/background.md](docs/background.md#生态谱系)

---

## 关键结论（截至 2026-09）

1. **两个方案的上游根本不是一回事**：one-api/new-api 的原料是 **API key**，CPA/sub2api 的原料是**订阅账号**。混着比会绕晕。
2. **CLIProxyAPI 是社区最成熟的方案**：51.2k star，Go，MIT，活跃。
3. **CPA 原生输出 Anthropic 端点**，Claude Code `ANTHROPIC_BASE_URL` 直接指过去即可，不需要中间再挂转换层。
4. **中间每多一层就多一次协议转换**，工具调用语义和计费口径都在转换里丢。已知 new-api + CPA 两层组合会出现工具调用与计费冲突。
5. **官方风控针对的是「多人共享/转售」这个行为，不是某个工具**。OpenAI Codex 负责人 Tibo 公开点名过 sub2api 的共享用法会被反欺诈系统标记，同时明确个人凭 Sign in with ChatGPT 正常使用不受影响。

---

## 本机（方案 A 已初始化）

目标：Codex 订阅 → 本机 CPA `:8317` → Claude Code 或以后的 Pi。当前 Claude Code **仍走原 provider（qax）**，没有切全局。

| 项 | 值 |
|---|---|
| 二进制 | Homebrew `cliproxyapi` 7.2.155 |
| 配置 | `~/.cli-proxy-api/config.yaml`（`127.0.0.1:8317`，chmod 600） |
| brew 路径 | `/opt/homebrew/etc/cliproxyapi.conf` → 上面那份 symlink |
| cc-switch | provider 名 `cpa-codex`，**未**设为 current |
| 常驻 | 未开 `brew services`（要跑用脚本，用完停） |

```bash
cd ~/utils/ai-sub-gateway
./scripts/cpa-login.sh          # ChatGPT OAuth，回调 :1455；chatgpt.com 要能打开
./scripts/cpa-start.sh
./scripts/cpa-status.sh         # 登录成功后 /v1/models 才有 ID
cc-switch start claude cpa-codex   # 临时开 Claude Code，不污染全局
./scripts/cpa-stop.sh
```

Pi 未装。Pi 官方支持 Sign in with ChatGPT（Tibo 点名的「正常客户端」），接 Codex **不一定要经 CPA**。CPA 主要是给 Claude Code 这种 Anthropic 协议客户端做一层转换。

密钥在 `~/.cli-proxy-api/config.yaml` 与本仓 `.env`（均 gitignore）。不要提交、不要回显全文。

---

## 待补

- [x] 方案 A 本机安装 + 配置样例（`config.example.yaml`）+ cc-switch `cpa-codex`
- [ ] 方案 A 模型映射三件套（等 `cpa-login` 后按 `/v1/models` 实表填）
- [ ] 方案 B 部署清单与拼车分工约定
- [ ] 两个方案的实测记录（额度消耗、稳定性、工具调用表现）

---

## 相关

- 私有 tkt CLI：`~/utils/toolkit`
- 公开 skill 合集：`~/utils/tkt-skills`
- 个人 Agent OS：`~/utils/agent-os`

工作区：`~/utils/tkt.code-workspace`
