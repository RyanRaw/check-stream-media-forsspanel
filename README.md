# Introduce
The code for this script to detect streaming media unlocking is all from the open source project [https://github.com/lmc999/RegionRestrictionCheck](https://github.com/lmc999/RegionRestrictionCheck) , and the open source protocol is AGPL-3.0. This script is open source as required by the open source license. Thanks to the original author @lmc999 and everyone who made the pull request for this project for their contributions.

该分支在原有检测脚本基础上适配 SSPanel 流媒体检测上报，并提供一键安装脚本。

检测逻辑已同步上游 `check.sh` v1.0.1（BBC iPLAYER / MyTVSuper / Bilibili / AbemaTV / Netflix / YouTube Premium / Disney+ / ChatGPT），资源文件 `cookies` 与 `reference/IATACode.txt` 保持与上游一致。

另参考 [xykt/IPQuality](https://github.com/xykt/IPQuality) 补充了 TikTok / Amazon Prime Video / Reddit 三项解锁检测，并采用其 `contentRegion`、`currentTerritory`、`country` 等信息更详细的区服判据。

同时新增三列 IP 维度信息（面板动态渲染，无需改动面板前端）：

| 列名 | 含义 | 取值示例 | 数据来源 |
| --- | --- | --- | --- |
| `UnlockType` | DNS 是否被劫持/污染（IPQuality 的 Native 判定） | `Native` / `DNS Hijack (netflix.com)` | `dig` / `nslookup` 解析随机子域 |
| `IPType` | IP 属性 | `Hosting` / `ISP` / `Mobile` / `Business`，代理类会附加 `(VPN, Proxy, Tor)` | `ipinfo.io/widget/demo`，依次回退 `ip-api.com`（仅 IPv4）、`ip.sb`（仅运营商名） |
| `IPRisk` | 定性风险等级 | `Low` / `Medium`（机房）/ `High`（VPN/代理/Tor）/ `unknown`（仅兜底源可用） | 由 `hosting/proxy/vpn/tor` 推导 |

出口 IP 由 `api64.ipify.org`、`api.ip.sb`、`ipinfo.io/ip`、`ifconfig.me`、`ip-api.com` 多源兜底获取（IPv4 优先，失败再试 IPv6）。`UnlockType` 与 `IPRisk` 均为纯本地判定，不依赖第三方接口；`IPType` 需要一次外部查询，所有数据源都不可用时这两列写 `Unknow`，不影响其余检测与上报。

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
  "OpenAI":     {"status": "yes"},
  "Reddit":     {"status": "no", "region": "MY", "type": "native"},
  "UnlockType": "Native",
  "IPType":     "Hosting (VPN)",
  "IPRisk":     "High"
}
```

| 字段 | 取值 |
| --- | --- |
| `status` | `yes` / `no` / `unknown`（网络异常）/ `soon`（Disney+ 即将上线） |
| `region` | 区服码（`US`、`TW`、`HK`…），或描述值：`oversea`（Abema 海外可用）、`originals`（Netflix 仅自制剧）、`banned`（Disney+ 封禁 IP）、`web` / `app`（ChatGPT 仅网页 / 仅 APP） |
| `type` | `native`（DNS 未被污染）/ `dns`（DNS 被劫持），取自 `UnlockType` 检测 |

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
- `cookies`、`reference/`：检测所需的 Cookie 与参考数据，脚本运行时会从本仓库拉取。

# 安装产物

以默认安装目录 `$HOME` 为例：

- `$HOME/csm.sh`：检测脚本
- `$HOME/.csm.config`：面板配置（依次为面板地址、mu key、节点 ID、X-Node-Token，第 4 行可留空）
- `$HOME/media_test_tpl.json`：检测报告（上报成功后自动删除）
- 定时任务：`0 */N * * * /bin/bash $HOME/csm.sh`

可通过环境变量 `CSM_DIR` 自定义以上文件所在目录。
