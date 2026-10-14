# Introduce
The code for this script to detect streaming media unlocking is all from the open source project [https://github.com/lmc999/RegionRestrictionCheck](https://github.com/lmc999/RegionRestrictionCheck) , and the open source protocol is AGPL-3.0. This script is open source as required by the open source license. Thanks to the original author @lmc999 and everyone who made the pull request for this project for their contributions.

该分支在原有检测脚本基础上适配 SSPanel 流媒体检测上报，并提供一键安装脚本。

检测逻辑已同步上游 `check.sh` v1.0.1（BBC iPLAYER / MyTVSuper / Bilibili / AbemaTV / Netflix / YouTube Premium / Disney+ / ChatGPT），资源文件 `cookies` 与 `reference/IATACode.txt` 保持与上游一致。

另参考 [xykt/IPQuality](https://github.com/xykt/IPQuality) 补充了 TikTok / Amazon Prime Video / Reddit 三项解锁检测，并采用其 `contentRegion`、`currentTerritory`、`country` 等信息更详细的区服判据；Google Gemini 的判据取自上游 `check.sh` 的 `WebTest_Gemini`。

同时新增以下 IP 维度字段（面板动态渲染，无需改动面板前端）：

| 列名 | 类型 | 含义与取值 | 数据来源 |
| --- | --- | --- | --- |
| `UnlockType` | 字符串 | DNS 是否被劫持/污染：`Native` / `DNS Hijack (netflix.com)` | `dig` / `nslookup` 解析随机子域 |
| `IPType` | 字符串 | 使用地与注册地一致为 `Native`（原生 IP），不一致为 `Broadcast`（广播 IP） | 使用地取 ipinfo `country`；注册地取 RIR 的 RDAP 数据（`rdap.org`，语义等同 MaxMind `RegisteredCountry`），失败回退 ipinfo `abuse.country` |
| `IPattributes` | 字符串 | IP 使用类型：`host` / `isp` / `mobile` / `business` / `education` / `government` / `other` | ASN 使用类型（ipinfo / ip-api） |
| `IPRisk` | 字符串 | `Low` / `Medium`（机房）/ `High`（VPN/代理/Tor）/ `unknown`（仅兜底源可用） | 由 `hosting/proxy/vpn/tor` 推导 |
| `UsageRegion` | 对象 | 使用地：`{"code":"JP","name":"日本","continent":"AS","continent_name":"亚洲"}` | ipinfo 使用地 + `reference/region_zh.tsv` |
| `RegisteredRegion` | 对象 | 注册地：`{"code":"ZA","name":"南非"}` | RIR 注册国（RDAP）+ `reference/region_zh.tsv` |
| `GoogleRegion` | 字符串 | Google 对出口 IP 的地区判定（两位码，如 `US`；判成 `CN` 即俗称的**送中**） | YouTube 首页 `ytInitialData.countryCode`（**Google 自己的判定**），失败回退 YouTube Premium 页；取不到上报空串 |

出口 IP 由 `api64.ipify.org`、`api.ip.sb`、`ipinfo.io/ip`、`ifconfig.me`、`ip-api.com` 多源兜底获取（IPv4 优先，失败再试 IPv6）。`UnlockType` 为纯本地判定；其余字段需要外部查询，依次尝试 `ipinfo.io/widget/demo` → `ip-api.com`（仅 IPv4）→ `api.ip.sb`（仅运营商信息，此时 `IPRisk` 为 `unknown`）；全部失败时 `IPType` / `IPattributes` 为空字符串、地区对象为 `null`，不影响其余检测与上报。`GoogleRegion` 是唯一取自「Google 自己」的字段（其余归属地来自 ipinfo / RIR）：判成 `CN` 时面板解锁页会把该节点标红。

# 2026-10-14 口径修正：Gemini / Reddit 判不准

## Gemini：从「恒判 No」到「能打开页面 ≠ 能用」

这一项改了两轮，别只看到第一轮：

**第一轮（v2.6.1）**：上游 `check.sh`（含本脚本原实现）判 Gemini 的方式是「页面里匹配 `45631641,null,true`」。Google 现在的应用页里
**已经没有任何**这个标记（实测出口在台湾、Gemini 明确可用时，795KB 页面里命中 **0** 次）→ 旧逻辑必然恒判 `No`（线上 12 个节点全是 `no`），上游至今未修。

**第二轮（v2.6.2，重要）**：改成「看页面能不能打开」是**错的** —— `gemini.google.com` 是个 SPA，
`/`、`/app`、`/faq` 返回**同一个壳**（实测 `/app` 与 `/` 完全一样，795KB），Google 不提供 Gemini 的地区**照样把壳发下来**，
于是香港 / 澳门这类节点被误判成可用（线上澳门节点就报过 `yes/MO`，而它的出口 Reddit 报的是 `HKG`）。

真正的地区判定藏在页面内联数据里：

```
,2,1,200,"XXX"        ← Google 自己判定的三字码地区（实测 TW 出口拿到 TWN）
```

判据（与社区现行实现 `lff/subs-check` 一致）：

| 情况 | 结果 |
|---|---|
| 三字码命中**封禁表** | `No`（页面照样能打开，但实际用不了；输出会带上 Google 判定的地区，便于核对）|
| 三字码不在封禁表 | `Yes (Region: <出口 IP 二字码>)` |
| 页面为空 | `Failed (Network Connection)` → `Unknow` |
| 页面拿到但没有地区码（同意页 / 风控页）| `Unknow`（不谎报可用）|

封禁表 = `CHN RUS BLR CUB IRN PRK SYR HKG MAC`（`GEMINI_BLOCKED_ALPHA3`），都是 Google 官方不提供 Gemini 的地区。
表变了改这一行即可。

> 顺带说明：`45631641` 这个"功能配置项"现在确实还在页面里，但形态变了 —— 从 `45631641,null,true` 变成转义 JSON 里的开关映射
> `\"45631641\":true`，且它在可用地区也是 `true` 之外的值时有出现，作为可用性判据并不可靠，故不再使用。

## Reddit：同一节点忽上忽下

原实现只认 `/svc/shreddit/reddit-chat` 的 `200` / `403`，且把 **403 直接判成 `No`**。但 Reddit 对机房 IP 会**不定时**回 403（反爬/限流），
与「该地区是否可用」无关 —— 线上实测同一个纽约节点 08:00 报 `yes/US`、12:00 报 `no`，就是被这个 403 打的。

现在：主接口拿不到 `country="XX"` 时，用网页端 `old.reddit.com`（页面里同样写 `country="XX"`）再探一次；
只有**两次都没拿到地区**才判 `No`，**两次都没响应**才是 `Failed (Network Connection)`。

> 验证（v2.6.2，本地出口台湾真跑 + 合成页面）：Gemini 判据单元测试、完整判定链路（TWN→Yes / HKG / MAC / CHN / RUS→No / 无地区码→Unknow /
> 无响应→Failed）、Reddit 四种控制流，共 **32 项全过**。

# 上报格式

接口：`POST {面板地址}/mod_mu/media/save_report?key={mu_key}&node_id={节点ID}`，鉴权使用 URL 查询参数 `key`（面板不读请求头，该参数不可省略）；同时附带节点 Token 请求头 `X-Node-Token`（取值见 `.csm.config` 第 4 行，留空时回退使用 mu key）；body 为 `content=base64(JSON)`，用 `--data-urlencode` 提交（base64 中的 `+` 会被正确编码并在面板侧还原）。失败时自动回退旧接口名 `saveReport`。

流媒体项的值升级为对象，分别上报状态 / 地区 / 方式；`UnlockType` / `IPType` / `IPRisk` 仍为字符串：

```json
{
  "Netflix":    {"status": "yes", "region": "MY", "type": "native"},
  "DisneyPlus": {"status": "no",  "region": "MY", "type": "native"},
  "TikTok":     {"status": "yes", "region": "MY", "type": "dns"},
  "YouTube":    {"status": "yes", "region": "MY", "type": "native"},
  "AmazonPV":   {"status": "yes", "region": "MY", "type": "native"},
  "Abema":      {"status": "yes", "region": "oversea", "type": "native"},
  "BBC":        {"status": "no",  "region": "originals", "type": "native"},
  "OpenAI":     {"status": "app", "region": "MO"},
  "Gemini":     {"status": "yes", "region": "TW", "type": "native"},
  "Reddit":     {"status": "no", "region": "MY", "type": "native"},
  "UnlockType": "Native",
  "IPType":     "Broadcast",
  "IPattributes": "host",
  "IPRisk":     "Low",
  "UsageRegion":      {"code": "JP", "name": "日本", "continent": "AS", "continent_name": "亚洲"},
  "RegisteredRegion": {"code": "ZA", "name": "南非"},
  "GoogleRegion":     "US"
}
```

| 字段 | 取值 |
| --- | --- |
| `status` | `yes` / `no` / `soon`（Disney+ 即将上线）/ `web`（ChatGPT 仅网页可用）/ `app`（ChatGPT 仅 APP 可用）/ `unknown`（网络异常） |
| `region` | 区服码（`US`、`TW`、`MO`…；ChatGPT 取出口 IP 所在地区），或描述值：`oversea`（Abema 海外可用）、`originals`（Netflix 仅自制剧）、`banned`（Disney+ 封禁 IP） |
| `type` | `native`（DNS 未被污染）/ `dns`（DNS 被劫持），取自 `UnlockType` 检测 |

# 送中（Google 判 CN）

`GoogleRegion` 判成 `CN` 时，面板解锁页会在该节点标题旁标红 **`Google 判定：中国大陆 (CN) · 送中`** ——
此时 YouTube Premium、Gemini 等按地区限制的服务会认为你在中国大陆而不可用。

判定取自 **Google 自己的数据**：YouTube 首页 `ytInitialData` 里的 `countryCode`（实测：出口在台湾时返回 `TW`）；
YouTube 不通时上报空串，面板侧不显示该徽章，也不影响其余检测。

两类常见起因与处理：

1. **用户端开着定位权限**（Chrome 的网站位置信息、手机 GPS）：Google 会把定位信号与该 IP 关联 —— 让用户关掉后过一段时间会自行恢复（面板 `/user/server` 页也有这句提示）；
2. **IP 段本身的问题**（注册地在中国大陆、广播 IP、被转手过的二手 IP）：只能换 IP / 换上游；Google 没有面向 IP 的公开纠错入口。

> 想用面板的**审计规则**（`DetectRule`）防送中是行不通的：它匹配的是用户访问的内容（正则 + 记录/断连/封号），与 IP 归属判定无关。

# How to use

## 一键安装（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/RyanRaw/check-stream-media-forsspanel/main/install.sh)
```

安装脚本会依次完成：安装依赖（curl / coreutils / cron / python）→ 下载 `csm.sh` → 写入面板配置（面板地址 / mu key / 节点 ID / X-Node-Token）→ 添加定时任务 → 立即执行一次检测并上报。

也支持非交互式安装：

```bash
bash install.sh -a https://demo.sspanel.org -k <mu_key> -n <node_id> -i 1
```

参数说明：

| 参数 | 说明 |
| --- | --- |
| `-a` | 面板地址，如 `https://demo.sspanel.org` |
| `-k` | 节点通讯密钥（mu key，即 URL 参数 `key`） |
| `-n` | 面板中的节点 ID |
| `-t` | `X-Node-Token`，缺省回车则上报时回退使用 mu key |
| `-i` | 定时检测间隔（小时，1-24，缺省交互选择） |
| `-d` | 安装目录，默认 `$HOME` |
| `-h` | 查看帮助 |

## Alpine Linux

Alpine 默认只有 busybox（ash），脚本会自动通过 `apk` 补齐 `bash`、`curl`、`coreutils`、`bind-tools`、`python3`，并用 OpenRC 启动 `crond`。安装前至少需要有 `bash` 与 `curl`（或 `wget`）：

```bash
apk add --no-cache bash curl
bash <(curl -fsSL https://raw.githubusercontent.com/RyanRaw/check-stream-media-forsspanel/main/install.sh)
```

若 `crond` 未运行，安装脚本会执行 `rc-update add crond default` 与 `rc-service crond start`；纯容器环境也可手动 `crond` 后台启动。

## 仅下载检测脚本

```
wget https://raw.githubusercontent.com/RyanRaw/check-stream-media-forsspanel/main/csm.sh
bash csm.sh
```

# Files

- `csm.sh`：流媒体解锁检测 + 结果上报脚本，也是定时任务实际执行的脚本。
- `install.sh`：一键安装 / 更新脚本。
- `cookies`、`reference/`：检测所需的 Cookie 与参考数据（`IATACode.txt`、`region_zh.tsv` 地区中文名表），脚本运行时会从本仓库拉取。

# 安装产物

以默认安装目录 `$HOME` 为例：

- `$HOME/csm.sh`：检测脚本
- `$HOME/.csm.config`：面板配置（依次为面板地址、mu key、节点 ID、X-Node-Token，第 4 行可留空）
- `$HOME/media_test_tpl.json`：检测报告（上报成功后自动删除）
- 定时任务：`0 */N * * * /bin/bash $HOME/csm.sh`

可通过环境变量 `CSM_DIR` 自定义以上文件所在目录。
