# 背景：生态谱系 · 上游机制 · 封号原理

> 这份文档是跨方案的公共背景。方案 A / B 的细节各自成文。
> 数据核对时间：2026-09-10。star 数等均为 `gh api` 实测，非搜索摘要。

---

## 生态谱系

这个圈子里最容易被绕晕的地方：**两类东西被混为一谈，但它们的上游根本不是一回事。**

```
【A 类 · API Key 网关】—— 原料是 API key
  解决的问题：我有一堆 API key，怎么统一格式、管理、分发给多人

  one-api   songquanpeng/one-api
    36830★ · JavaScript(Node.js) · MIT · 最后提交 2026-01-09 ← 已停滞 8 个月
    元祖。统一 API 适配、key 管理与二次分发
      ↓ 二次开发（数据库兼容，可平滑迁移）
  new-api   QuantumNous/new-api
    47793★ · Go · AGPL-3.0 · 活跃
    已反超 one-api；多格式互转（OpenAI / Claude / Gemini）

  ⚠️ 注意：网上普遍称 one-api 是 Go 写的，错。gh api 返回 "lang":"JavaScript"。


【B 类 · 订阅转 API】—— 原料是订阅账号（OAuth）
  解决的问题：我有订阅但没有 key，怎么把订阅额度变成 API

  CLIProxyAPI   router-for-me/CLIProxyAPI
    51229★ · Go · MIT · 活跃
    轻量、单二进制、个人自用

  sub2api   Wei-Shaw/sub2api
    41100★ · Go · LGPL-3.0 · 3177 open issues
    拼车共享、内置支付，是 A + B 的合体
```

### 一句话记住

**`sub2api` 这个名字就是答案：sub**scription **2** **api**。它把「A 类的分发能力」焊到了「B 类的订阅上游」上——所以才会有支付系统、Token 计费、给下游发 key 这些 A 类网关的标配。

### 安全提醒（别忽略）

- **new-api**：有一批 2026 年披露的 CVE——IDOR 权限绕过、两个 SSRF、一个 SQLi/DoS。要用就沙箱跑、限制出网、及时打补丁
- **one-api**：社区反馈「一堆安全漏洞没修、很久没更新」，`2026-01-09` 后无提交
- **自建服务第一件事：改默认管理员密码**。有站长因为没改，被 87 个 IP 盗用、一天涌进 60 多个注册

---

## 上游机制（以 Codex 为例）

### 链路

```
Claude Code CLI
  │  Anthropic 协议 POST /v1/messages（ANTHROPIC_BASE_URL 指过来）
  ▼
中转层（CPA / sub2api）
  │  ① 协议转换  Anthropic → Codex
  │  ② 头部伪装  codex-tui 指纹
  │  ③ OAuth token 鉴权
  ▼
https://chatgpt.com/backend-api/codex     ← 关键：不是 api.openai.com
```

### 三个要点

**① 不 spawn codex CLI 子进程。** 上游就是普通 HTTPS 请求，走 OAuth token（`~/.codex/auth.json` 那一套），不是 API key。所以本机不需要装 codex CLI。

**② 上游是 ChatGPT 后端，不是 OpenAI 官方 API。** 端点是 `chatgpt.com/backend-api/codex`——走的是订阅额度通道，不是 metered API。

**③ 伪装成 Codex TUI 客户端。** CLIProxyAPI 的做法（源码实证）：

- `internal/runtime/executor/codex_executor_request.go:26-28`
  ```go
  codexUserAgent = "codex-tui/0.153.3 (Mac OS 26.5.1; arm64) iTerm.app/3.6.11 (codex-tui; 0.153.3)"
  codexOriginator = "codex-tui"
  ```
- 项目内部管这套叫 **cloaking**，配置开关 `codex.disable-codex-cloaking`（默认 `false`）
- 下游客户端的 User-Agent **被主动剥掉**，注释理由是「减少 Cloudflare 1010 拦截」
- 会识别并剥离 Claude Code 注入的归因 system 文本（`codex_claude_request.go:70`）——既解决兼容，客观上也抹掉了「这是 Claude Code 在调用」的痕迹

**协议转换层**在 `internal/translator/codex/claude/`：Claude 的 `system` → Codex 的 `instructions`，system message → developer input content。**只转一层**——这就是 CPA 直连相比「再套一层 new-api」的核心优势。

---

## 封号原理

### 官方表态（OpenAI Codex 负责人 Tibo Sottiaux）

回应 Codex 额度缩水争议时明确讲了三点：

1. 受影响的用户里，相当比例在**用 sub2api**
2. 把订阅转成 API 流量后**对外转售或分享给多名用户**，不是 OpenAI 支持的用法，**这类流量会被反欺诈风控系统标记**
3. **个人正常使用不受影响**——Sign in with ChatGPT 用订阅没问题，官方客户端、以及支持 ChatGPT 账号登录的开源客户端（Pi、OpenCode）都没问题

**后续反转**：Tibo 补充说目前**未发现整体用量系统异常**，之前提 sub2api 只是在解释团队发现的「一种特定情况」，**不能解释所有**用户配额突然耗尽的问题。且有用官方客户端的用户也反馈额度缩水。

**讽刺的上下文**：Tibo 一个月前还公开推荐过 CLIProxyAPI。

> **一句话结论**：官方风控针对的是 **「多人共享/转售」这个行为**，不是某个具体工具。用哪个工具是次要变量，怎么用是主要变量。

### 三个真实风险源（按权重）

**① 并发会话数（最重要）**

真实 Codex CLI 是人对着终端单会话交互。Claude Code 会并行开子代理、后台跑辅助请求（文件摘要、会话标题、命令描述）——这些**全部**变成额外的 Codex 请求。行为差异是伪装层盖不住的。

**② 网络环境**

机房 IP 段、共享代理、频繁跨国跳 IP、被标记的代理 IP。社区有帖子反馈过「端口换高位、路径伪装、苟了快一个月」最后还是没逃掉。

> 有说法称「家宽反而比机房更容易触发」，与主流建议矛盾，**无可靠依据，存疑**。

**③ 账号来源与支付**

菲区代开、礼品卡、虚拟卡、黑卡、同卡多号、买号——这些是**独立的封号通道**，跟用不用反代无关。

### 社区实际经验分布（公开论坛反馈，非官方）

- 反方：菲区 20xPro 一人一号、只反代不碰网页，**仍被封**；「两个号放 CPA 自用，没活过 8 天」
- 正方：有人 CPA 用了 **4 个月**没事；sub2api 用了 **3 个月**没事
- 有观察称**被封帖里 CPA 占比高于 sub2api**——但官方点名的是 sub2api，说明该观察很可能有样本偏差

### 个人使用的风险压法（按杠杆排序）

**高杠杆**

1. **单账号，不拼车。** 社区共识「最大风险就是拼车高并发」。号池里堆多个号反而危险（一个出事连坐）
2. **压并发。** `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=3`，让节奏接近真人交互式使用
3. **映射好小模型。** Claude Code 后台杂活量大，`ANTHROPIC_DEFAULT_HAIKU_MODEL` / `SONNET` / `OPUS` 三个都要配，不映射就是拿贵模型刷额度
4. **关 1M 上下文。** `CLAUDE_CODE_DISABLE_1M_CONTEXT=1`——Codex 后端没这个能力，开着只会制造异常请求

**中杠杆**

5. **网络稳定。** 固定出口，别频繁跳 IP，避开明显的共享/机房段
6. **别关 cloaking。** `disable-codex-cloaking` 保持 `false`

**低杠杆 / 与反代无关**

7. 正价自付、不用代开/礼品卡/虚拟卡
8. 不碰破限、逆向、爬虫类内容
9. **先用小号验，别拿主号赌**

### 后果不可逆

ChatGPT 和 Codex **共用账号体系**。封号是账号级的——网页版、Codex CLI、API key 会**一起**失效。

---

## 参考来源

- [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) · [官方文档](https://help.router-for.me/)
- [Wei-Shaw/sub2api](https://github.com/Wei-Shaw/sub2api)
- [songquanpeng/one-api](https://github.com/songquanpeng/one-api) · [QuantumNous/new-api](https://github.com/QuantumNous/new-api)
- [OpenAI 回应 Codex 使用限制：sub2api 转售共享会触发风控 — IT之家](https://m.ithome.com/html/992767.htm)
- [负责人 Tibo 回应 Codex 额度大幅缩水](https://grapecity.csdn.net/6a8844b710ee7a33f29d899f.html)
- [ChatGPT 与 Codex 封号常见六大原因及自查排查指南（2026版）](https://cloud.tencent.com.cn/developer/article/2688138)
- [【求助】Claude Code使用Codex 模型：工具调用与计费冲突（new-api + CPA）— LINUX DO](https://linux.do/t/topic/2028355)
- [One API vs New API：开源 Token 中转站怎么选？— APISIX](https://www.apiseven.com/one-api-vs-new-api)
