# 故障排查手册（TROUBLESHOOTING.md）

> 内容来自实机部署踩坑记录与社区反馈，按出现频率排序。

## 快速索引

| 你遇到的现象 | 跳到 |
|---|---|
| 市场上装完，重启后第一次很慢 / 失败 | [问题 1](#问题-1市场装完重启后第一次很慢--失败) |
| 想看插件到底卡在哪一步 | [问题 2](#问题-2怎么读自举日志bootstraplog) |
| `apt-get update` 大量 404（binary-amd64） | [问题 3](#问题-3apt-get-update-报-404binary-amd64packages) |
| 下载 Chromium 报 404（NoSuchKey） | [问题 4](#问题-4playwright-下载-chromium-报-404npmmirror-无-arm64-build) |
| 重启 MCP 报 `Unknown error` | [问题 5](#问题-5restart_mcp_with_logs-报-unknown-error) |
| 重启报错但插件其实能用 | [问题 6](#问题-6重启报-unknown-error但-ping_mcp-正常) |
| 插件永远加载不上 / 日志有 NPE | [问题 7](#问题-7插件永远加载不上--日志出现-npepluginmetadata-字段缺失) |
| 网站弹「安全验证」/验证码 | [问题 8](#问题-8百度等站点弹出安全验证headless-风控) |
| 截图/产物找不到在哪 | [问题 9](#问题-9截图产物落盘位置) |
| MCP 启动成功但浏览器报错 | [问题 10](#问题-10mcp-启动成功但浏览器报错) |
| 工具数是 24 不是 25 | [问题 11](#问题-11ping_mcp-显示-24-个工具不是文档说的-25-个) |

---

## 问题 1：市场装完，重启后第一次很慢 / 失败

**现象**：从 Operit 市场安装插件後，重启 MCP 时卡很久，或直接报启动失败；再重启一次又正常了。

**原因（正常行为）**：插件采用**自举设计**。首次启动时，转发器要完成两件重活：

1. 自动 `npm install` 下载 `@playwright/mcp`（几十 MB）；
2. 本机没有 Chromium 时，自动下载（约 150MB，数分钟）。

若 Operit 对 MCP 启动有超时限制，第一次可能在你等完之前就被判为失败。

**处理**：

```bash
# 看进度 / 确认是否已完成
cat ~/mcp_plugins/playwright_mcp/bootstrap.log

# 或手动预完成（避免首次启动超时）
cd ~/mcp_plugins/playwright_mcp
npm install --no-audit --no-fund
```

完成后在 Operit 内**再重启一次 MCP** 即可。

> 💡 若不希望自动下载，可在 `mcpServers.playwright_mcp.env` 里设 `PW_MCP_AUTO_DOWNLOAD=0` 并自行准备 Chromium。

## 问题 2：怎么读自举日志（bootstrap.log）

**位置**：`~/mcp_plugins/playwright_mcp/bootstrap.log`（与转发器同目录，即插件的 Linux 运行目录）。

```bash
# 实时跟踪
tail -f ~/mcp_plugins/playwright_mcp/bootstrap.log

# 看最后 30 行
tail -30 ~/mcp_plugins/playwright_mcp/bootstrap.log
```

日志会逐行说明：node 路径、MCP 包来源（本地/全局/自动安装）、Chromium 路径与 build 号、启动命令。排查时先把这份日志发出来，基本能定位到具体哪一步。

## 问题 3：apt-get update 报 404（binary-amd64/Packages）

**现象**：`apt-get update` 大量 `404 Not Found .../dists/noble/main/binary-amd64/Packages`，装不了依赖库。

**根因**：`/etc/apt/sources.list.d/` 里有 amd64 架构的源（如 `deb [arch=amd64] ...`），而系统 dpkg 又注册了 amd64 foreign arch；主 sources.list（ubuntu-ports，只有 arm64）因此也会被要求拉取 amd64 包列表 → 404。

**修复**：

```bash
# 1. 备份并移除 amd64 源文件
mv /etc/apt/sources.list.d/amd64.list /etc/apt/sources.list.d/amd64.list.bak

# 2. 主源强制限定 arm64（dpkg 的 amd64 arch 可能无法 remove：database in use）
sed -i 's|^deb |deb [arch=arm64] |' /etc/apt/sources.list

apt-get update
```

## 问题 4：playwright 下载 Chromium 报 404（npmmirror 无 arm64 build）

**现象**：

```
Failed to download Chrome for Testing ... (playwright chromium v1237)
server returned code 404 body '...NoSuchKey...'
```

**根因**：`@playwright/mcp` 自带 playwright 是 alpha 版（要求较新 revision，如 1237），npmmirror 镜像尚未同步该版本的 `chromium-linux-arm64.zip`。

**修复（首选）**：不下载，复用本机已装 Chromium：

```bash
find ~/.cache/ms-playwright -maxdepth 4 -type f -name chrome -path '*chrome-linux*' -size +1M
# 推荐：把路径交给转发器（无需改代码）
export PLAYWRIGHT_CHROME_BIN=/root/.cache/ms-playwright/chromium-1237/chrome-linux/chrome
```

实测 1234/1237（旧版稳定）被 0.0.80 的 playwright-core（1.63-alpha）驱动**完全兼容**（CDP 向后兼容）。

**备选**：换官方 CDN：`PLAYWRIGHT_DOWNLOAD_HOST=https://playwright.download.prss.microsoft.com/dbazure/download/playwright`（国内可能慢/不通）。

## 问题 5：restart_mcp_with_logs 报 Unknown error

**现象**：修改 `mcp_config.json` 后重启 MCP，工具直接报 `Unknown error`，`ping_mcp` 也找不到插件。

**根因（两种）**：

1. Operit 的 stdio 本地插件**在 Linux 侧 `~/mcp_plugins/<id>/` 启动**，Android 源目录不会自动同步；目录缺失时启动流程直接异常。
2. **venv 缺失**：启动命令是 `venv/bin/python -m playwright_mcp`，而 Operit 只在「安装/重装」时创建 venv，单纯重启不会重建。

**修复**：

```bash
# 补 Linux 侧目录
cp -r /sdcard/Download/Operit/mcp_plugins/playwright_mcp ~/mcp_plugins/

# 补 venv
cd ~/mcp_plugins/playwright_mcp && python3 -m venv venv

# 然后 Operit 内 restart_mcp_with_logs → 预期全部 success
# （或用一键脚本：bash install.sh）
```

## 问题 6：重启报 Unknown error，但 ping_mcp 正常

**现象**：`restart_mcp_with_logs` 返回 `Unknown error`，但去插件状态页看是「已安装」，`ping_mcp(playwright_mcp)` 也能列出 24 个工具。

**结论：这不是故障**。Operit 的重启工具在部分情况下会抛出错误，但插件实际已成功加载。

**判定标准**：**以 `ping_mcp` 能否列出 24 个 `browser_*` 工具为准**（能列出 = 正常工作）。

## 问题 7：插件永远加载不上 / 日志出现 NPE（pluginMetadata 字段缺失）

**现象**：配置照抄了「精简版」片段后，插件加载失败、重启报空指针；Operit 日志可见 `MCPRepository.kt` 的 `metadata.copy()` 抛 NPE（`updatedAt` 为 null）。

**根因**：`pluginMetadata.playwright_mcp` 缺少 `updatedAt` / `longDescription` / `logoUrl` / `installedTime` 等非空字段。

**修复（v1.0.4 起根治）**：使用仓库 [config/mcp_config.json](../config/mcp_config.json) 全字段模板，或直接跑新版 `install.sh`（自动生成 15 字段完整 pluginMetadata 并合并，原配置自动备份）。**不要再手写精简片段**。

## 问题 8：百度等站点弹出「安全验证」（headless 风控）

**现象**：`navigate` 正常，但执行搜索/提交后跳转到验证码页（`wappass.baidu.com/static/captcha/...`）。

**原因**：headless Chromium 的自动化特征被 WAF 识别，属预期行为，不影响自动化能力本身。

**缓解**：

- `--user-agent` 指定真实浏览器 UA（可用 `PW_MCP_EXTRA_ARGS` 追加）
- 用 `--storage-state` 预置带登录态的 cookie 文件
- 换无风控的目标站测试核心能力

## 问题 9：截图/产物落盘位置

**现象**：`browser_take_screenshot` 返回相对路径，找不到文件。

**说明**：MCP 进程 cwd = `~/mcp_plugins/playwright_mcp/`（Linux 侧）。

- 指定 `filename` → 存 cwd 根目录
- 不指定 → 存 `.playwright-mcp/` 子目录（snapshot / console 日志同处）

```bash
ls ~/mcp_plugins/playwright_mcp/.playwright-mcp/
```

## 问题 10：MCP 启动成功但浏览器报错

常见于系统依赖库缺失。**必装**：

```bash
npx playwright install-deps chromium
```

包含 `libxkbcommon0`、`libnss3`、`libnspr4`、`libatk`、`libcups`、`libdrm`、`libgbm`、`libasound2`、`fonts-unifont`（中文字体）等。

> 💡 `install.sh` 会在探测到 Chromium 后自动 `ldd` 检查并列出缺失库，先看它的输出。

## 问题 11：ping_mcp 显示 24 个工具，不是文档说的 25 个？

**24 个是正确的**。官方 `@playwright/mcp` v0.0.80（npm stable）的 `browser_*` 工具就是 24 个：

`click` / `close` / `console_messages` / `drag` / `drop` / `evaluate` / `file_upload` / `fill_form` / `find` / `handle_dialog` / `hover` / `navigate` / `navigate_back` / `network_request` / `network_requests` / `press_key` / `resize` / `run_code_unsafe` / `select_option` / `snapshot` / `tabs` / `take_screenshot` / `type` / `wait_for`

早期文档（v1.0.0）中的「25」笔误已在 **v1.0.1 及以后版本**修正。如果少于 24 个，请检查版本是否为 0.0.80：

```bash
cat ~/mcp_plugins/playwright_mcp/bootstrap.log   # 会打印实际使用的 cli.js 路径
node -e "console.log(require('/usr/lib/node_modules/@playwright/mcp/package.json').version)"
```
