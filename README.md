# Introduce
The code for this script to detect streaming media unlocking is all from the open source project [https://github.com/lmc999/RegionRestrictionCheck](https://github.com/lmc999/RegionRestrictionCheck) , and the open source protocol is AGPL-3.0. This script is open source as required by the open source license. Thanks to the original author @lmc999 and everyone who made the pull request for this project for their contributions.

该分支在原有检测脚本基础上适配 SSPanel 流媒体检测上报，并提供一键安装脚本。

检测逻辑已同步上游 `check.sh` v1.0.1（BBC iPLAYER / MyTVSuper / Bilibili / AbemaTV / Netflix / YouTube Premium / Disney+ / ChatGPT），资源文件 `cookies` 与 `reference/IATACode.txt` 保持与上游一致。

# How to use

## 一键安装（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/RyanRaw/check-stream-media-forsspanel/main/install.sh)
```

安装脚本会依次完成：安装依赖（curl / coreutils / cron / python）→ 下载 `csm.sh` → 写入面板配置 → 添加定时任务 → 立即执行一次检测并上报。

也支持非交互式安装：

```bash
bash install.sh -a https://demo.sspanel.org -k <mu_key> -n <node_id> -i 1
```

参数说明：

| 参数 | 说明 |
| --- | --- |
| `-a` | 面板地址，如 `https://demo.sspanel.org` |
| `-k` | 节点通讯密钥（mu key） |
| `-n` | 面板中的节点 ID |
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
- `$HOME/.csm.config`：面板配置（依次为面板地址、mu key、节点 ID）
- `$HOME/media_test_tpl.json`：检测报告（上报成功后自动删除）
- 定时任务：`0 */N * * * /bin/bash $HOME/csm.sh`

可通过环境变量 `CSM_DIR` 自定义以上文件所在目录。
