# 故障排查手册（TROUBLESHOOTING.md）

> 内容来自实机部署踩坑记录与社区反馈，按出现频率排序。

## 快速索引

| 你遇到的现象 | 跳到 |
|---|---|
| 市场上装完，重启后第一次很慢 / 失败 | [问题 1](#问题-1市场装完重启后第一次很慢--失败) |
| 想看插件到底卡在哪一步 | [问题 2](#问题-2怎么读自举日志bootstraplog) |
| `apt-get update` 大量 404（binary-amd64） | [问题 3](#问题-3apt-get-update-报-404binary-amd64packages) |
| 下载 Chromium 报 404（NoSuchKey） | [问题 4](#问题-4playwright-下载-chromium-报-404npmmirror-无-arm64-build) |
| 新版 Chromium 一启动就崩（SIGTRAP / exit 133） | [问题 13](#chromium-sigtrap) |
| 重启 MCP 报 `Unknown error` | [问题 5](#问题-5restart_mcp_with_logs-报-unknown-error) |
| 重启报错但插件其实能用 | [问题 6](#问题-6重启报-unknown-error但-ping_mcp-正常) |
| 插件永远加载不上 / 日志有 NPE | [问题 7](#问题-7插件永远加载不上--日志出现-npepluginmetadata-字段缺失) |
| 网站弹「安全验证」/验证码 | [问题 8](#问题-8百度等站点弹出安全验证headless-风控) |
| 截图/产物找不到在哪 | [问题 9](#问题-9截图产物落盘位置) |
| MCP 启动成功但浏览器报错 | [问题 10](#问题-10mcp-启动成功但浏览器报错) |
| npm install 报 ETARGET（alpha 依赖找不到） | [问题 12](#问题-12npm-install-报-etarget) |
| 工具数是 25 不是旧文档说的 24 | [问题 11](#问题-11ping_mcp-显示-25-个工具旧文档说-24) |
| 插件启用了但 MCP 不响应 / 握手超时 | [问题 14](#mcp-not-responding) |

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
cat ~/mcp_plugins/playwrightmcp/bootstrap.log

# 或手动预完成（避免首次启动超时）
cd ~/mcp_plugins/playwrightmcp
npm install --no-audit --no-fund
```

完成后在 Operit 内**再重启一次 MCP** 即可。

> 💡 若不希望自动下载，可在 `mcpServers.playwrightmcp.env` 里设 `PW_MCP_AUTO_DOWNLOAD=0` 并自行准备 Chromium。

## 问题 2：怎么读自举日志（bootstrap.log）

**位置**：`~/mcp_plugins/playwrightmcp/bootstrap.log`（与转发器同目录，即插件的 Linux 运行目录）。

```bash
# 实时跟踪
tail -f ~/mcp_plugins/playwrightmcp/bootstrap.log

# 看最后 30 行
tail -30 ~/mcp_plugins/playwrightmcp/bootstrap.log
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

> **实测（2026-09-19，旧驱动）**：`chromium-1237` 在 `playwright-core 1.63/1.64-alpha` 下完全兼容（CDP 向后兼容；实测 0.0.82 启动正常、导航成功）。
>
> ⚠️ **但新版反而会崩（2026-09-23 实测）**：rev1246+（CFT 154.x）在 proot 下启动即 SIGTRAP，详见 [问题 13](#chromium-sigtrap)。所以「复用本机 Chromium」时要用的始终是 **1237**，不是最新版。
>
> **实测（2026-11-14，新驱动）**：`chromium-1237` 与 `playwright-core 1.66.0-alpha-2026-11-09` 交叉验证通过——API 直测 launch / 截图 / 执行 JS / 点击全通，真实 MCP 协议 initialize → tools/list(25) → navigate → snapshot → evaluate → close 全链路 3.5 秒。
>
> **结论**：优先复用本机已有的 `chromium-1237`，不要盲目下载，也不要升级到 1246+。

**备选**：换官方 CDN：`PLAYWRIGHT_DOWNLOAD_HOST=https://playwright.download.prss.microsoft.com/dbazure/download/playwright`（国内可能慢/不通）。

## 问题 5：restart_mcp_with_logs 报 Unknown error

**现象**：修改 `mcp_config.json` 后重启 MCP，工具直接报 `Unknown error`，`ping_mcp` 也找不到插件。

**根因（两种）**：

1. Operit 的 stdio 本地插件**在 Linux 侧 `~/mcp_plugins/<id>/` 启动**，Android 源目录不会自动同步；目录缺失时启动流程直接异常。
2. **venv 缺失**：启动命令是 `venv/bin/python -m playwrightmcp`，而 Operit 只在「安装/重装」时创建 venv，单纯重启不会重建。

**修复**：

```bash
# 补 Linux 侧目录
cp -r /sdcard/Download/Operit/mcp_plugins/playwrightmcp ~/mcp_plugins/

# 补 venv
cd ~/mcp_plugins/playwrightmcp && python3 -m venv venv

# 然后 Operit 内 restart_mcp_with_logs → 预期全部 success
# （或用一键脚本：bash install.sh）
```

## 问题 6：重启报 Unknown error，但 ping_mcp 正常

**现象**：`restart_mcp_with_logs` 返回 `Unknown error`，但去插件状态页看是「已安装」，`ping_mcp(playwrightmcp)` 也能列出 25 个工具。

**结论：这不是故障**。Operit 的重启工具在部分情况下会抛出错误，但插件实际已成功加载。

**判定标准**：**以 `ping_mcp` 能否列出 25 个 `browser_*` 工具为准**（能列出 = 正常工作）。

## 问题 7：插件永远加载不上 / 日志出现 NPE（pluginMetadata 字段缺失）

**现象**：配置照抄了「精简版」片段后，插件加载失败、重启报空指针；Operit 日志可见 `MCPRepository.kt` 的 `metadata.copy()` 抛 NPE（`updatedAt` 为 null）。

**根因**：`pluginMetadata.playwrightmcp` 缺少 `updatedAt` / `longDescription` / `logoUrl` / `installedTime` 等非空字段。

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

**说明**：MCP 进程 cwd = `~/mcp_plugins/playwrightmcp/`（Linux 侧）。

- 指定 `filename` → 存 cwd 根目录
- 不指定 → 存 `.playwright-mcp/` 子目录（snapshot / console 日志同处）

```bash
ls ~/mcp_plugins/playwrightmcp/.playwright-mcp/
```

## 问题 10：MCP 启动成功但浏览器报错

常见于系统依赖库缺失。**必装**：

```bash
npx playwright install-deps chromium
```

包含 `libxkbcommon0`、`libnss3`、`libnspr4`、`libatk`、`libcups`、`libdrm`、`libgbm`、`libasound2`、`fonts-unifont`（中文字体）等。

> 💡 `install.sh` 会在探测到 Chromium 后自动 `ldd` 检查并列出缺失库，先看它的输出。

## 问题 11：ping_mcp 显示 25 个工具（旧文档说 24）？

**25 个是正确的**。官方 `@playwright/mcp` v0.0.85（npm stable）的 `browser_*` 工具实际是 25 个（旧文档漏列 `emulate_media`）：

`click` / `close` / `console_messages` / `drag` / `drop` / `evaluate` / `file_upload` / `fill_form` / `find` / `handle_dialog` / `hover` / `navigate` / `navigate_back` / `network_request` / `network_requests` / `press_key` / `resize` / `emulate_media` / `run_code_unsafe` / `select_option` / `snapshot` / `tabs` / `take_screenshot` / `type` / `wait_for`

如果少于 25 个，请先确认版本确实是 **0.0.85**（v0.0.80 及更早为 24 个）：

```bash
cat ~/mcp_plugins/playwrightmcp/bootstrap.log   # 会打印实际使用的 cli.js 路径
node -e "console.log(require('/usr/lib/node_modules/@playwright/mcp/package.json').version)"
```

---

## 问题 12：npm install 报 ETARGET

**现象**：`npm install`（或首次启动自举）失败，日志提示：

```
npm error code ETARGET
npm error notarget No matching version found for playwright-core@1.66.0-alpha-2026-11-09.
```

**根因**：`@playwright/mcp@0.0.85` 依赖的是 **alpha 预发布版** 的 playwright-core
（形如 `1.66.0-alpha-<时间戳>`）。国内镜像 `registry.npmmirror.com` **默认不同步 alpha / prerelease 版本**，
所以查不到这个版本号 —— 这与插件本身无关，是镜像同步策略导致的。

**解决**：改用官方源。

从 **v1.0.6 起，`install.sh` 与转发器已默认使用官方源**，正常安装不会遇到此问题；
只有手动安装、或本机 npm 默认源已设为镜像时才会碰到：

```bash
# 手动安装：显式指定官方源
npm install --registry https://registry.npmjs.org

# 或通过环境变量（install.sh 与转发器都会读取）
export PW_MCP_NPM_REGISTRY=https://registry.npmjs.org
```

> 💡 命令行 `--registry` 的优先级高于 `.npmrc`，因此即使本地默认源是镜像也会生效。

**验证**：

```bash
node -e "console.log(require('@playwright/mcp/package.json').version)"
# 应输出 0.0.85

---

<a id="chromium-sigtrap"></a>

## 问题 13：proot 下新版 Chromium（rev1246+）一启动就崩（SIGTRAP / exit 133）

**现象**（2026-09-23，@bingfengcxl-crypto 在 Operit + proot Ubuntu24 aarch64 上报告）：

- `chrome --version` 能正常打印，但**一旦真启动**（`--headless` 打开页面 / Playwright 驱动）立刻挂掉；
- 直接跑：`Trace/breakpoint trap`，**exit code 133（SIGTRAP）**；
- Playwright 侧报：`browser.newPage: Target page, context or browser has been closed`；
- verbose 日志里 GPU 进程反复崩溃：`GPU process exited unexpectedly: exit_code=5`。

```bash
# 复现（新版 154.x / rev1246）
./chrome --headless --no-sandbox --disable-gpu --dump-dom 'data:text/html,<h1>x</h1>'
# → Trace/breakpoint trap（exit 133）
```

**根因**：新版 Chrome for Testing（154.0.8037.0 / rev1246）在 proot 下的 GPU 与沙箱探测路径不受支持。
据报告者实测（2026-09-23），以下常见 flag **都救不回来**：`--single-process`、`--no-zygote`、`--disable-dev-shm-usage`、
`--disable-gpu`、`GLIBC_TUNABLES=glibc.pthread.rseq=0`。

**修复：用 chromium-1237，不要用新版**（约 195 MB，npmmirror 镜像与官方源字节一致）：

```bash
curl -L -o chromium-1237.zip \
  "https://cdn.npmmirror.com/binaries/playwright/builds/chromium/1237/chromium-linux-arm64.zip"
# 204,922,677 字节
# ⚠️ 这个 zip 的第一层直接就是 chrome-linux/，没有 chromium-1237/ 顶层目录，
#   所以要自己先建好目录再解压（2026-09-23 实测确认）
mkdir -p ~/.cache/ms-playwright/chromium-1237
unzip -q chromium-1237.zip -d ~/.cache/ms-playwright/chromium-1237
ls ~/.cache/ms-playwright/chromium-1237/chrome-linux/chrome
```

最保险是在插件 `env` 里直接指死（跳过一切自动探测）：

```json
{
  "PLAYWRIGHT_CHROME_BIN": "/root/.cache/ms-playwright/chromium-1237/chrome-linux/chrome"
}
```

> ✅ **v1.0.7 起**：转发器内置偏好 —— 本机同时存在多个 build 时**优先选 1237**
> （`PW_MCP_PREFERRED_BUILD`，默认 `1237`；设 `0` 关闭偏好）。

**验证**：

```bash
./chrome --headless --no-sandbox --disable-gpu --dump-dom 'data:text/html,<h1>hi1237</h1>'
# → exit 0，输出 <html><head></head><body><h1>hi1237</h1></body></html>
```

```

---

<a id="mcp-not-responding"></a>

## 问题 14：插件启用了，但 MCP 不响应 / 握手超时

**症状**：启用插件后，AI 侧调用工具长时间无响应，最终报 `MCP server not responding` 或握手超时。

### ✅ 先看 UI：最新 Beta 版会直接告诉你原因

**Operit 1.12.2+2（versionCode 53）起**，MCP 启动桥改成了「失败时把真实原因回传 UI」：

```yaml
旧版（bridge v52 及更早）：
  helper 进程启动失败 → 一直等到超时 → UI 只显示「not responding」
  → 看不出发生了什么，必须自己查进程和日志

新版（versionCode 53+）：
  helper 在 report ready 之前退出 → 立即把失败原因回传 UI
  → 会给出 stderr、缺环境变量、入口路径错误、进程崩溃 这几类具体原因
```

**所以排查顺序应该是：**

```yaml
1. 先看 Operit UI 的报错（插件页 / MCP 设置页）
2. UI 已写明原因 → 直接按原因处理，不必跑下面的三查法
3. UI 只说「超时 / not responding」→ 才继续往下看三查法
```

> ⚠️ **注意**：这个能力**只在最新 Beta 版（1.12.2+2 / versionCode 53 及以上）才有**。
> 旧版即使盯着 UI 看也看不出原因，必须靠下面的三查法。
>
> 本节的「三查法」对两个版本都适用，只是新版通常不需要走到这一步。

### 先理解启动链

```
Operit（App） → node /root/bridge/spawn-helper.js → venv/bin/python -m playwrightmcp
```

`/root/bridge/` 由 App **每次启动时整份释放**。所以：

> **桥没被调用 → 插件不可能起来。**

### ⚠️ 最常见的误判：文件是新的 ≠ 桥被拉起来了

很多人看到 `/root/bridge/index.js` 时间戳是新的，就以为桥已经就绪。实际上：

```yaml
文件存在且是新的  → 只能说明 App 释放过文件
                  → 不能说明 App 去调用了它
```

如果 App 根本没调桥，会同时看到两件事：

```yaml
桥文件存在、且时间戳很新     ← 果
进程表里没有任何 bridge 进程  ← 果
```

**这是同一个原因的两个结果，不是一个导致另一个。** 看到前者不能推出“桥正常”。

### 三查法（按顺序做）

**① 查进程（最关键）**

```bash
ps aux | grep -E 'bridge|spawn-helper|playwright' | grep -v grep
```

成功时应看到**三条**：

```yaml
1. node /root/bridge/index.js
2. node /root/bridge/spawn-helper.js（通常两个实例）
3. node .../node_modules/@playwright/mcp/cli.js --headless --no-sandbox --executable-path .../chromium-1237/...
```

> ⭐ **第三条出现，才等于 MCP 握手成功、插件真的被拉起来。**
>
> - 只有前两条 → 桥起来了，但插件没起来
> - 一条都没有 → App 压根没调桥

**② 查 App 日志**

```bash
L=$(ls -t /sdcard/Download/Operit/packageLogs/*.log 2>/dev/null | head -1)
grep -inE 'bridge|mcp|spawn|playwright' "$L" | head -20
```

如果日志里只有 `loadAvailablePackages start/finish` 这类包扫描行，**没有任何 bridge / mcp / spawn 相关行** → App 这一轮根本没有尝试拉起任何 MCP 插件。

**③ 查插件自举日志（最直接）**

```bash
cat ~/mcp_plugins/playwrightmcp/bootstrap.log
```

成功时末尾应有完整记录：

```
[时间][INFO] 自举启动（插件目录：...）
[时间][INFO] node = /usr/bin/node
[时间][INFO] MCP CLI = .../cli.js（来源：插件本地 node_modules）
[时间][INFO] Chromium = .../chromium-1237/chrome-linux/chrome（build=1237）
[时间][INFO] 启动 MCP server：...
```

如果这个文件**不存在，或 mtime 不更新** → 插件根本没被启动过。

### 端到端验证（唯一能证明“能用”的一步）

进程和日志都正常，仍要实际跑一次：

```yaml
1. browser_navigate → 任意网站
2. 确认返回里有 Page Title
3. browser_take_screenshot → 应产出 PNG
4. 确认文件真的落到磁盘
```

**只有截图真的生成、页面标题真的读出来，才算闭环。**

### 其他常见误判

**① 有 UI 权限 ≠ 无障碍服务在跑**

工具调用返回：

```
Accessibility service is not enabled
```

此时插件本身可能是好的，只是**系统无障碍服务没开**。开启路径：

```
设置 → 无障碍（辅助功能）→ 已下载的服务 → Operit → 打开 → 允许查看和控制屏幕
```

这项与插件无关，任何 UI 自动化工具都会受它影响。

**② 只换文件不重启 App**

桥由 App 每次启动时释放，**改完文件必须完全退出 App 再重开**（从后台清掉），否则桥不会重载。

**③ 用 `find /` 扫全盘定位文件**

在手机 / proot 下极慢（很容易超过 20 秒）。改用 `ls -t`、定点 `grep`，或用已知的绝对路径。

### 判别表

| 进程情况 | 含义 | 下一步 |
|---|---|---|
| 三条都有（桥 ×2 + cli.js） | 正常 | 直接跑端到端验证 |
| 只有桥进程，无 cli.js | 插件启动失败 | 看 `bootstrap.log` 找原因 |
| 一条都没有 | App 没调桥 | 重启 App；确认插件 `isInstalled=true` 且 `disabled=false` |
| 有 cli.js 但无桥进程 | 异常（几乎不会发生） | 检查是否有残留进程 |
