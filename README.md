# Playwright MCP for Operit

[![version](https://img.shields.io/badge/version-1.0.0-4A90D9?style=flat-square)](https://github.com/x15907982411/playwright-mcp-for-operit)
[![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

在 **Operit（Android / arm64 proot）** 中运行官方 [@playwright/mcp](https://github.com/microsoft/playwright-mcp) 的部署方案：headless Chromium + **25 个 `browser_*` 工具**，为 Operit 提供完整网页自动化能力，**替代失效的内置 `browser` 包**。

## 为什么需要这个仓库（背景）

Operit 内置 `browser` 包存在兼容性问题（壳可用、内核不通：页面永远 Loading、JS 全超时）。而 Operit 对**本地 stdio MCP 插件**的支持非常成熟（Exa / Skill Seekers / MT APK MCP 均已验证）。

本项目 = **零代码修改**，仅通过部署方案（配置 + 脚本 + 文档）把官方 Playwright MCP 接入 Operit：

| 方案对比 | 自研 Operit 包 | **官方 @playwright/mcp（本方案）** | 纯 proot 脚本 |
|---|---|---|---|
| 造轮子 | 高 | **零** | 中 |
| 工具面 | 未知 | **与原 browser 包等价（25 工具）** | 拼命令，体验差 |
| 成功率 | 低 | **高**（实测全链路通过） | 中 |

## 特性

- ✅ **官方 MCP server**，零自研代码，工具面 `browser_navigate / browser_snapshot / browser_click / browser_type / browser_take_screenshot / browser_evaluate` 等 25 个
- ✅ **arm64 实测可用**：headless Chromium 跑在 proot（Ubuntu 24 / aarch64）内，真实渲染、真实交互
- ✅ **零额外浏览器下载**：自动复用已安装的 playwright chromium（`--executable-path`），版本不匹配时可自动下载
- ✅ **全链路实测通过**：导航（标题真实渲染）→ snapshot（完整无障碍树 + ref 定位）→ 输入/点击（真实跳转）→ 截图（渲染完整落盘）
- ✅ 网络抓包（network_requests）、console 日志、文件上传、多标签等增强能力

## 快速开始（一键脚本）

```bash
bash install.sh
```

脚本自动：检查 node/npm → 安装 @playwright/mcp → 定位/下载 chromium（arm64 headless）→ 生成配置。

## 手动部署（3 步）

### 1. 安装依赖（proot 内）

```bash
npm i -g @playwright/mcp                          # 官方 MCP server（国内：npm config set registry https://registry.npmmirror.com）
npx playwright install-deps chromium              # 系统依赖库（libxkbcommon 等）
```

### 2. 注册到 Operit

在 `/sdcard/Download/Operit/mcp_plugins/mcp_config.json` 的 `mcpServers` 与 `pluginMetadata` 中添加（完整样例见 [config/mcp_config.json](./config/mcp_config.json)，含注释版见 [docs/DEPLOY.md](./docs/DEPLOY.md)）：

```json
"mcpServers": {
  "playwright_mcp": {
    "command": "node",
    "args": [
      "/usr/lib/node_modules/@playwright/mcp/cli.js",
      "--headless",
      "--no-sandbox",
      "--executable-path",
      "/root/.cache/ms-playwright/chromium-1234/chrome-linux/chrome"
    ],
    "disabled": false,
    "env": {}
  }
}
```

> 💡 `--no-sandbox` 是 @playwright/mcp 官方原生 CLI 参数（proot 环境必需）；`--executable-path` 指向已安装的 chromium，避免重复下载。

### 3. 双路径部署 + 重启

```bash
mkdir -p /sdcard/Download/Operit/mcp_plugins/playwright_mcp
cp mcp.config.json /sdcard/Download/Operit/mcp_plugins/playwright_mcp/
cp -r /sdcard/Download/Operit/mcp_plugins/playwright_mcp /root/mcp_plugins/
```

Operit 内触发 `restart_mcp_with_logs`（预期 4/4 success），`ping_mcp(playwright_mcp)` 应列出 25 个工具。

## 使用方式

```text
use_package playwright_mcp   # 激活
→ playwright_mcp:browser_navigate  →  playwright_mcp:browser_snapshot
→ playwright_mcp:browser_click     →  playwright_mcp:browser_take_screenshot
```

工具面与官方 Playwright MCP 完全一致，AI 可无缝迁移。

## 可用工具（25 个）

`browser_navigate` · `browser_navigate_back` · `browser_snapshot` · `browser_click` · `browser_type` · `browser_fill_form` · `browser_hover` · `browser_select_option` · `browser_drag` · `browser_drop` · `browser_press_key` · `browser_tabs` · `browser_resize` · `browser_take_screenshot` · `browser_wait_for` · `browser_find` · `browser_evaluate` · `browser_run_code_unsafe` · `browser_network_requests` · `browser_network_request` · `browser_console_messages` · `browser_handle_dialog` · `browser_file_upload` · `browser_close`

## 踩坑记录（详见 [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md)）

1. **apt 源 404**：`sources.list.d/amd64.list` 配了 amd64 源但系统注册了 amd64 foreign arch（无法移除）→ 主 sources.list 每行加 `[arch=arm64]` 限定
2. **chromium 版本不匹配**：@playwright/mcp 自带 playwright 为 alpha 版（要求新 revision，npmmirror 无 arm64 build）→ 用 `--executable-path` 复用已装版本，实测跨 minor 版本完美兼容
3. **`restart_mcp_with_logs` 报 Unknown error**：Linux 侧 `/root/mcp_plugins/<id>/` 目录缺失 → 先复制 Android 源目录过去再重启
4. **百度等站点对 headless 有风控**（触发安全验证）→ 换 UA / 带 cookie 可缓解

## 回滚

删除 `mcp_config.json` 中 `playwright_mcp` 条目 + 双路径目录 → `restart_mcp_with_logs`。

## 上游信息

- 上游 MCP server：https://github.com/microsoft/playwright-mcp（v0.0.79）
- 浏览器内核：Chromium headless（arm64，playwright 管理）
- 运行环境：Operit + proot Ubuntu 24（aarch64）

## License

MIT — 本项目仅含部署脚本/文档，MCP server 版权归 [Microsoft Playwright MCP](https://github.com/microsoft/playwright-mcp) 所有。
