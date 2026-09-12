# 手动部署手册（DEPLOY.md）

> 适用环境：Operit（Android）+ proot Ubuntu 24（aarch64）。
> 本文记录完整手动部署流程；一键脚本见 [install.sh](../install.sh)（v1.0.5 已自动完成第 1~6 步）。

## 目录

- [0. 前置检查](#0-前置检查)
- [1. 准备插件目录](#1-准备插件目录)
- [2. 安装 Node 依赖](#2-安装-node-依赖)
- [3. 写入 Operit 配置](#3-写入-operit-配置)
- [4. 双路径部署](#4-双路径部署)
- [5. venv 与重启验证](#5-venv-与重启验证)
- [6. 自举机制（为什么装完就能用）](#6-自举机制为什么装完就能用)
- [7. 使用方法](#7-使用方法)
- [8. 卸载](#8-卸载)

---

## 0. 前置检查

```bash
node -v && npm -v          # 需要 node >= 18（实测 v24）
nproc && uname -m          # 本方案针对 aarch64
free -m                    # 建议可用内存 >= 1GB（Chromium headless 约占 300-500MB）
```

## 1. 准备插件目录

插件目录（Android 源侧）：`/sdcard/Download/Operit/mcp_plugins/playwright_mcp/`，需包含 4 个文件：

| 文件 | 作用 |
|---|---|
| `playwright_mcp.py` | **自举转发器**（必须）。新版 Operit 用 `venv/bin/python -m playwright_mcp` 启动，靠它把请求转给真正的 MCP server |
| `requirements.txt` | 让 Operit 判定为 PYTHON 项目（可只写注释，无 Python 依赖） |
| `package.json` | 声明 Node 依赖 `@playwright/mcp`，供 Operit 自动 `npm install` |
| `mcp.config.json` | 标志文件（内容 = 配置里的 `mcpServers` 部分） |

```bash
D=/sdcard/Download/Operit/mcp_plugins/playwright_mcp
mkdir -p "$D"
cp scripts/playwright_mcp.py "$D/"
cp requirements.txt          "$D/"
cp package.json              "$D/"
cp config/mcp_config.json    "$D/mcp.config.json"
```

## 2. 安装 Node 依赖

⚠️ **必须在 Linux 文件系统内安装**（`/sdcard` 是 FUSE，不支持文件锁与符号链接，在里面跑 npm 会失败或产生半成品）。因此先把插件目录复制到 Linux 侧再装：

```bash
# 先复制到 Linux 侧
rm -rf ~/mcp_plugins/playwright_mcp
cp -r /sdcard/Download/Operit/mcp_plugins/playwright_mcp ~/mcp_plugins/

# 方式 A：本地安装（推荐）
cd ~/mcp_plugins/playwright_mcp && npm install --no-audit --no-fund

# 方式 B：全局安装
npm i -g @playwright/mcp@0.0.80

# 方式 C：什么都不做 —— 首次启动时转发器会自动补齐（见第 6 节）
```

> ⚠️ `@playwright/mcp` 自带的 playwright 依赖为 **alpha 版**（1.63.0-alpha），其要求的 Chromium revision 可能比稳定版新。**不要盲目下载**（npmmirror 镜像可能没有 arm64 build，返回 404）——优先复用已有 Chromium。

## 3. 写入 Operit 配置

**直接复制仓库 [config/mcp_config.json](../config/mcp_config.json)（v1.0.5 全字段模板）**，将其中 `playwright_mcp` 条目合并进 Operit 的 `/sdcard/Download/Operit/mcp_plugins/mcp_config.json`。

两个关键约束：

1. **启动命令是 Python，不是 node**。新版 Operit（2026-08-22 起）强制按「目录名 = 模块名」启动，使用 `venv/bin/python -m playwright_mcp`，因此 `mcpServers.command` 为 `venv/bin/python`（或 `~/mcp_plugins/playwright_mcp/venv/bin/python`），`args` 为 `["-m", "playwright_mcp"]`，且**必须配套 `playwright_mcp.py`**。
2. **`pluginMetadata` 必须 15 字段全量**：`id` / `name` / `version` / `updatedAt` / `installedTime` / `isInstalled` / `logoUrl` / `longDescription` / `author` / `repoUrl` / `description` / `type` / `connectionType` / `installedPath` / `disabled`。缺失 `updatedAt` 等字段会导致 Operit 加载插件时空指针异常（MCPRepository NPE），表现为「永远加载不上」。

模板核心（完整版见 [config/mcp_config.json](../config/mcp_config.json)）：

```jsonc
{
  "mcpServers": {
    "playwright_mcp": {
      "command": "~/mcp_plugins/playwright_mcp/venv/bin/python",  // PYTHON 项目启动形式
      "args": ["-m", "playwright_mcp"],                           // 配合自举转发器
      "autoApprove": [],
      "disabled": false,
      "env": {}
    }
  },
  "pluginMetadata": {
    "playwright_mcp": {
      "author": "x15907982411",
      "connectionType": "stdio",
      "description": "Playwright MCP - 网页自动化（导航/点击/填表/截图/snapshot）",
      "disabled": false,
      "id": "playwright_mcp",
      "installedPath": "/storage/emulated/0/Download/Operit/mcp_plugins/playwright_mcp",
      "installedTime": 1788600000000,
      "isInstalled": true,
      "logoUrl": "",
      "longDescription": "基于官方 @playwright/mcp 的网页自动化插件（24 个 browser_* 工具）。",
      "name": "Playwright MCP for Operit",
      "repoUrl": "https://github.com/x15907982411/playwright-mcp-for-operit",
      "type": "local",
      "updatedAt": "2026-09-12T00:00:00Z",
      "version": "1.0.5"
    }
  }
}
```

## 4. 双路径部署

Operit 的 stdio 插件需要**同时存在两份目录**（缺 Linux 侧会导致重启报 `Unknown error`）：

```bash
# Linux 运行目录（先清旧目录，避免旧文件残留）
rm -rf ~/mcp_plugins/playwright_mcp
cp -r /sdcard/Download/Operit/mcp_plugins/playwright_mcp ~/mcp_plugins/
```

> 💡 若已按第 2 节做过本地 npm install，建议把 `node_modules` 一并带上（或让首次启动自举）。

## 5. venv 与重启验证

启动命令是 `venv/bin/python -m playwright_mcp`，而 **Operit 只在「安装/重装」插件时创建 venv，单纯重启不会重建**，所以手动部署必须自己建：

```bash
cd ~/mcp_plugins/playwright_mcp
python3 -m venv venv
./venv/bin/python -m playwright_mcp   # 能打印自举日志即正常（Ctrl+C 退出）
```

| 步骤 | 操作 | 预期结果 |
|---|---|---|
| 1 | Operit 内触发 `restart_mcp_with_logs` | 全部 success（首次启动可能较慢，见第 6 节） |
| 2 | `ping_mcp(playwright_mcp)` | 列出 **24 个 `browser_*` 工具**（以它为准，重启工具报错不代表失败） |
| 3 | 冒烟测试 `browser_navigate("https://www.baidu.com")` | 返回标题「百度一下，你就知道」 |

## 6. 自举机制（为什么装完就能用）

`playwright_mcp.py` 不只是一个转发器，它在启动前会按顺序自检并补齐环境：

| 顺序 | 检查项 | 缺失时的行为 |
|---|---|---|
| 1 | `node` | 报错并提示安装方式（可用 `NODE_BIN` 指定） |
| 2 | MCP 包：插件内 `node_modules` → 全局 `node_modules` | 都没有 → 自动 `npm install`（本地优先，回退全局） |
| 3 | Chromium：`PLAYWRIGHT_CHROME_BIN` → `~/.cache/ms-playwright`（含 `/root` 与 `PLAYWRIGHT_BROWSERS_PATH`） | 都没有 → 自动 `install chromium`（约 150MB） |
| 4 | 启动 | `exec` 到 `node cli.js --headless --no-sandbox --executable-path <chrome>` |

环境变量（写在 `mcpServers.playwright_mcp.env` 或系统环境中）：

| 变量 | 默认 | 作用 |
|---|---|---|
| `NODE_BIN` | 自动 | 指定 node 可执行文件 |
| `PLAYWRIGHT_CHROME_BIN` | 自动 | 指定 Chromium 可执行文件 |
| `PW_MCP_VER` | `0.0.80` | 自动安装时的版本 |
| `PW_MCP_MIN_BUILD` | `1243` | 低于此 build 仅告警 |
| `PW_MCP_AUTO_INSTALL` | `1` | `0` = 不自动安装 MCP 包 |
| `PW_MCP_AUTO_DOWNLOAD` | `1` | `0` = 不自动下载 Chromium |
| `PW_MCP_NPM_REGISTRY` | 系统 | 指定 npm 镜像 |
| `PW_MCP_EXTRA_ARGS` | 空 | 追加给 MCP server 的启动参数（空格分隔） |

诊断日志：`~/mcp_plugins/playwright_mcp/bootstrap.log`（同时输出到 stderr，Operit 日志可见）。

## 7. 使用方法

```js
use_package playwright_mcp
playwright_mcp:browser_navigate(url)
playwright_mcp:browser_snapshot()               // 无障碍树 + ref
playwright_mcp:browser_click(target: "e36")
playwright_mcp:browser_take_screenshot()
```

## 8. 卸载

```bash
bash uninstall.sh                # 移除双路径目录 + 配置条目（自动备份）
bash uninstall.sh --keep-files   # 只移除配置，保留文件
bash uninstall.sh --purge        # 连 Android 源目录（含 node_modules）一起删
# 然后 Operit 内 restart_mcp_with_logs
```

手动步骤：

```bash
# 1. 从 mcp_config.json 删除 playwright_mcp 两个条目（或用备份 .bak.* 恢复）
# 2. 删目录
rm -rf ~/mcp_plugins/playwright_mcp /sdcard/Download/Operit/mcp_plugins/playwright_mcp
# 3. Operit 内 restart_mcp_with_logs
```
