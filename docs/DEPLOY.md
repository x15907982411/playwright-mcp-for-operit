# 手动部署手册（DEPLOY.md）

> 适用环境：Operit（Android）+ proot Ubuntu 24（aarch64）。本文记录完整手动部署流程，一键脚本见 [install.sh](../install.sh)（v1.0.4 已自动完成 3~5 步并处理插件加载问题）。

## 0. 前置检查

```bash
node -v && npm -v          # 需要 node >= 18（实测 v24）
nproc && uname -m          # 本方案针对 aarch64
free -m                    # 建议可用内存 >= 1GB（chromium headless 约占 300-500MB）
```

## 1. 安装 @playwright/mcp（全局，锁版本）

```bash
npm i -g @playwright/mcp@0.0.80    # ⚠️ 必须锁版本！国内加速：npm config set registry https://registry.npmmirror.com
```

> ⚠️ @playwright/mcp 自带 playwright 依赖为 **alpha 版**（1.63.0-alpha），其要求的 chromium revision 可能比稳定版新。**不要盲目下载**（npmmirror 镜像可能没有 arm64 build，404）——优先走第 2 步的复用方案。

## 2. 准备 chromium（两种方式）

### 方式 A：复用已安装的 chromium（推荐，零下载）

如果本机已有任何 playwright chromium（如 1.62 稳定版）：

```bash
find ~/.cache/ms-playwright -maxdepth 4 -type f -name chrome -path '*chrome-linux*'
# 例：/root/.cache/ms-playwright/chromium-1237/chrome-linux/chrome
```

将路径填入配置的 `--executable-path`。**实测跨 minor 版本（1234/1237 → 1243）完美兼容**，CDP 协议向后兼容（0.0.80 需求 chromium build 1243，低于该 build 时脚本会给出提示，但复用实测可用）。

### 方式 B：安装匹配版本

```bash
cd /usr/lib/node_modules/@playwright/mcp
PLAYWRIGHT_DOWNLOAD_HOST=https://cdn.npmmirror.com/binaries/playwright node node_modules/playwright/cli.js install chromium
```

> 若镜像 404：说明该版本未同步 arm64 build，请回退方式 A（详见 [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) 问题 2）。

### 系统依赖库（首次必装）

```bash
npx playwright install-deps chromium
```

> ⚠️ 若 apt 报 404（amd64 Packages），见 [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) 问题 1。

## 3. 注册配置

**直接复制仓库 [config/mcp_config.json](../config/mcp_config.json)（v1.0.4 全字段模板）**，把其中 `playwright_mcp` 条目合并进 Operit 的 `/sdcard/Download/Operit/mcp_plugins/mcp_config.json`。

> ⚠️ 新版 Operit（2026-08-22 起）强制按「目录名=模块名」启动，用 `venv/bin/python -m playwright_mcp`。因此 **mcpServers 的 `command` 是 `venv/bin/python`**（不是 `node`），且 **必须配套 `playwright_mcp.py` 转发器**（见第 4 节）。直接复制下面的 config 模板即可，不要手写精简片段。

> ⚠️ `pluginMetadata.playwright_mcp` **必须包含全字段**（`id`/`name`/`version`/`updatedAt`/`installedTime`/`isInstalled`/`logoUrl`/`longDescription`/`author`/`repoUrl`/`description`/`type`/`connectionType`/`installedPath`/`disabled`）。缺失 `updatedAt` 等字段会导致 Operit 加载插件时空指针异常（MCPRepository NPE），表现为"永远加载不上"。**不要手写精简片段**。

模板核心（可复制，mcpServers 对齐 Operit 源码生成逻辑）：

```jsonc
{
  "mcpServers": {
    "playwright_mcp": {
      "command": "~/mcp_plugins/playwright_mcp/venv/bin/python",   // Operit 生成的绝对路径（PYTHON 项目）
      "args": ["-m", "playwright_mcp"],                             // 配合 playwright_mcp.py 转发器
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
      "longDescription": "Playwright MCP - 网页自动化（导航/点击/填表/截图/snapshot）",
      "name": "Playwright MCP for Operit",
      "repoUrl": "https://github.com/x15907982411/playwright-mcp-for-operit",
      "type": "local",
      "updatedAt": "2026-09-05T00:00:00Z",
      "version": "0.0.80"
    }
  }
}
```

## 4. 双路径部署

Operit 的 stdio 插件需要同时存在两份目录（**缺 Linux 侧会导致重启报 Unknown error**）：

```bash
# Android 源目录（含 mcp.config.json 标志文件 + playwright_mcp.py 转发器 + requirements.txt）
mkdir -p /sdcard/Download/Operit/mcp_plugins/playwright_mcp
cp config/mcp_config.json /sdcard/Download/Operit/mcp_plugins/playwright_mcp/mcp.config.json
cp scripts/playwright_mcp.py /sdcard/Download/Operit/mcp_plugins/playwright_mcp/playwright_mcp.py
touch /sdcard/Download/Operit/mcp_plugins/playwright_mcp/requirements.txt

# Linux 运行目录
cp -r /sdcard/Download/Operit/mcp_plugins/playwright_mcp /root/mcp_plugins/
```

> ⚠️ **`playwright_mcp.py` 转发器必须有**：新版 Operit 用 `venv/bin/python -m playwright_mcp` 启动，缺该文件会直接启动失败（`ModuleNotFoundError`）。`requirements.txt` 为空文件，用于让 Operit 判定为 PYTHON 项目。

## 5. 重启与验证

1. Operit 内触发 `restart_mcp_with_logs` → 预期全部 success（若有其他插件则总数相应变化）
2. `ping_mcp(playwright_mcp)` → 应列出 **24 个 `browser_*` 工具**（v0.0.80 stable 的正确数量，不是 25）
3. 冒烟测试：`browser_navigate("https://www.baidu.com")` → 标题应为"百度一下，你就知道"

## 6. 使用

```text
use_package playwright_mcp
→ playwright_mcp:browser_navigate(url)
→ playwright_mcp:browser_snapshot()          # 无障碍树 + ref
→ playwright_mcp:browser_click(target: "e36")
→ playwright_mcp:browser_take_screenshot()
```

## 回滚

```bash
# 1. 从 mcp_config.json 删除 playwright_mcp 两个条目（或用 install.sh 自动备份恢复）
# 2. 删除双路径目录
rm -rf /sdcard/Download/Operit/mcp_plugins/playwright_mcp /root/mcp_plugins/playwright_mcp
# 3. Operit 内 restart_mcp_with_logs
```