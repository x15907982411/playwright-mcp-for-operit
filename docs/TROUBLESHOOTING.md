# 故障排查手册（TROUBLESHOOTING.md）

> 全部来自 2026-08-07 实机部署踩坑记录，按出现频率排序。

## 问题 1：apt-get update 报 404（binary-amd64/Packages）

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

## 问题 2：playwright 下载 chromium 报 404（npmmirror 无 arm64 build）

**现象**：

```
Failed to download Chrome for Testing ... (playwright chromium v1237)
server returned code 404 body '...NoSuchKey...'
```

**根因**：@playwright/mcp 自带 playwright 是 alpha 版（要求较新 revision，如 1237），npmmirror 镜像尚未同步该版本的 `chromium-linux-arm64.zip`。

**修复（首选）**：不下载，复用本机已装 chromium：

```bash
CHROME=$(find ~/.cache/ms-playwright -maxdepth 4 -type f -name chrome -path '*chrome-linux*' | head -1)
# 在 mcp_config.json 的 args 中加：--executable-path $CHROME
```

实测 1234（1.62 稳定版）被 1.63-alpha 的 playwright-core 驱动**完全兼容**（CDP 向后兼容）。

**备选**：换官方 CDN 下载：`PLAYWRIGHT_DOWNLOAD_HOST=https://playwright.download.prss.microsoft.com/dbazure/download/playwright`（国内可能慢/不通）。

## 问题 3：restart_mcp_with_logs 报 Unknown error

**现象**：修改 mcp_config.json 后重启 MCP，工具直接报 `Unknown error`，ping_mcp 也找不到插件。

**根因**：Operit 的 stdio 本地插件**在 Linux 侧 `/root/mcp_plugins/<id>/` 启动**，Android 源目录不会自动同步；目录缺失时启动流程直接异常。

**修复**：先补 Linux 侧目录再重启：

```bash
cp -r /sdcard/Download/Operit/mcp_plugins/playwright_mcp /root/mcp_plugins/
# 然后 Operit 内 restart_mcp_with_logs → 预期 4/4 success
```

## 问题 4：百度等站点弹出"安全验证"（headless 风控）

**现象**：navigate 正常，但执行搜索/提交后跳转到验证码页（`wappass.baidu.com/static/captcha/...`）。

**原因**：headless Chromium 的自动化特征被 WAF 识别，属预期行为，不影响自动化能力本身。

**缓解**：
- `--user-agent` 指定真实浏览器 UA（CLI 参数）
- 用 `--storage-state` 预置带登录态的 cookie 文件
- 换无风控的目标站测试核心能力

## 问题 5：截图/产物落盘位置

**现象**：`browser_take_screenshot` 返回相对路径，找不到文件。

**说明**：MCP 进程 cwd = `~/mcp_plugins/playwright_mcp/`（Linux 侧）。
- 指定 `filename` → 存 cwd 根目录
- 不指定 → 存 `.playwright-mcp/` 子目录（snapshot/console 日志同处）

```bash
ls /root/mcp_plugins/playwright_mcp/.playwright-mcp/
```

## 问题 6：MCP 启动成功但浏览器报错

常见于系统依赖库缺失。**必装**：

```bash
npx playwright install-deps chromium
```

包含 libxkbcommon0、libnss3、libnspr4、libatk、libcups、libdrm、libgbm、libasound2、fonts-unifont（中文字体）等。
