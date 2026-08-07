# 手动部署手册（DEPLOY.md）

> 适用环境：Operit（Android）+ proot Ubuntu 24（aarch64）。本文记录完整手动部署流程，一键脚本见 [install.sh](../install.sh)。

## 0. 前置检查

```bash
node -v && npm -v          # 需要 node >= 18（实测 v24）
nproc && uname -m          # 本方案针对 aarch64
free -m                    # 建议可用内存 >= 1GB（chromium headless 约占 300-500MB）
```

## 1. 安装 @playwright/mcp（全局）

```bash
npm i -g @playwright/mcp          # 国内加速：npm config set registry https://registry.npmmirror.com
```

> ⚠️ @playwright/mcp 自带 playwright 依赖为 **alpha 版**（如 1.63.0-alpha），其要求的 chromium revision 可能比稳定版新。**不要盲目下载**（npmmirror 镜像可能没有 arm64 build，404）——优先走第 2 步的复用方案。

## 2. 准备 chromium（两种方式）

### 方式 A：复用已安装的 chromium（推荐，零下载）

如果本机已有任何 playwright chromium（如 1.62 稳定版）：

```bash
find ~/.cache/ms-playwright -maxdepth 4 -type f -name chrome -path '*chrome-linux*'
# 例：/root/.cache/ms-playwright/chromium-1234/chrome-linux/chrome
```

将路径填入配置的 `--executable-path`。**实测跨 minor 版本（1234 vs 1237）完美兼容**，CDP 协议向后兼容。

### 方式 B：安装匹配版本

```bash
cd /usr/lib/node_modules/@playwright/mcp
node node_modules/playwright/cli.js install chromium
```

> 若镜像 404：`PLAYWRIGHT_DOWNLOAD_HOST=https://cdn.npmmirror.com/binaries/playwright` 仍失败则说明该版本未同步 arm64，请回退方式 A。

### 系统依赖库（首次必装）

```bash
npx playwright install-deps chromium
```

> ⚠️ 若 apt 报 404（amd64 Packages），见 [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) 问题 1。

## 3. 注册配置

编辑 `/sdcard/Download/Operit/mcp_plugins/mcp_config.json`，在 `mcpServers` 和 `pluginMetadata` 中各加一段（完整可复制版本见 [config/mcp_config.json](../config/mcp_config.json)）：

```jsonc
{
  "mcpServers": {
    "playwright_mcp": {
      "command": "node",                                    // PATH 内命令即可
      "args": [
        "/usr/lib/node_modules/@playwright/mcp/cli.js",    // 全局安装路径
        "--headless",                                       // 无头模式
        "--no-sandbox",                                     // ⚠️ proot 必需（无 user namespace）
        "--executable-path",                                // 复用已装 chromium（方式 A）
        "/root/.cache/ms-playwright/chromium-1234/chrome-linux/chrome"
      ],
      "disabled": false,
      "env": {}
    }
  },
  "pluginMetadata": {
    "playwright_mcp": {
      "type": "local",
      "connectionType": "stdio",
      "id": "playwright_mcp",
      "installedPath": "/storage/emulated/0/Download/Operit/mcp_plugins/playwright_mcp",
      "isInstalled": true,
      "name": "Playwright MCP for Operit",
      "version": "0.0.79"
    }
  }
}
```

## 4. 双路径部署

Operit 的 stdio 插件需要同时存在两份目录（**缺 Linux 侧会导致重启报 Unknown error**）：

```bash
# Android 源目录（含标志文件 mcp.config.json）
mkdir -p /sdcard/Download/Operit/mcp_plugins/playwright_mcp
cp config/mcp_config.json /sdcard/Download/Operit/mcp_plugins/playwright_mcp/

# Linux 运行目录
cp -r /sdcard/Download/Operit/mcp_plugins/playwright_mcp /root/mcp_plugins/
```

## 5. 重启与验证

1. Operit 内触发 `restart_mcp_with_logs` → 预期 `4/4 success`（若有其他插件则总数相应变化）
2. `ping_mcp(playwright_mcp)` → 应列出 **25 个 `browser_*` 工具**
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
# 1. 从 mcp_config.json 删除 playwright_mcp 两个条目
# 2. 删除双路径目录
rm -rf /sdcard/Download/Operit/mcp_plugins/playwright_mcp /root/mcp_plugins/playwright_mcp
# 3. Operit 内 restart_mcp_with_logs
```