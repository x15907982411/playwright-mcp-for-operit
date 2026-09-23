# Playwright MCP for Operit

[![version](https://img.shields.io/badge/version-1.0.6-4A90D9?style=flat-square)](https://github.com/x15907982411/playwright-mcp-for-operit)
[![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-Android%20%2B%20proot%20arm64-blueviolet?style=flat-square)](#环境要求)
[![tools](https://img.shields.io/badge/browser__tools-25-orange?style=flat-square)](#它能做什么)
[![upstream](https://img.shields.io/badge/upstream-%40playwright%2Fmcp%400.0.82-black?style=flat-square)](https://github.com/microsoft/playwright-mcp)

> **为 Operit 装上真正的浏览器。**
>
> 让你的 AI 助手自己打开网页、阅读内容、搜索填表、截图取证——一切自动化，全程可观测。

本项目将微软官方的 [Playwright MCP](https://github.com/microsoft/playwright-mcp)（v0.0.82）接入 [Operit](https://github.com/AAswordman/Operit)（Android 上的 AI 助手）。基于 Chromium 内核，在手机上获得与桌面浏览器一致的渲染与交互能力。

---

## 目录

- [版本更新记录（CHANGELOG）](#changelog)
- [环境要求](#环境要求)
- [它能做什么](#它能做什么)
- [效果演示](#效果演示)
- [快速开始](#快速开始)
- [首次启动会发生什么](#首次启动会发生什么)
- [使用示例](#使用示例)
- [常见问题](#常见问题)
- [文档导航](#文档导航)
- [相关链接](#相关链接)
- [License](#license)

---

## 环境要求

| 项 | 要求 | 说明 |
|---|---|---|
| **运行平台** | Operit（Android）+ proot Ubuntu 24 | 本项目针对 `aarch64` 构建 |
| **Node.js** | ≥ 18（实测 v24） | 用于运行 MCP server |
| **可用内存** | ≥ 1GB | Chromium headless 约占 300–500MB |
| **磁盘空间** | ~150MB（仅在需下载 Chromium 时） | 已有 Chromium 则零下载 |

## 它能做什么

**25 个 `browser_*` 工具**，覆盖「打开 → 操作 → 取证」完整链路，工具面与官方 Playwright MCP v0.0.82 完全一致。

> v1.0.6 起新增 `browser_emulate_media`（模拟媒体类型/打印/深浅色）；另有 `browser_run_code_unsafe`（执行任意代码）——**该工具能力极强，仅在确认页面可信时使用**。

| 能力 | 说明 |
|---|---|
| 🧪 **模拟媒体环境** | `browser_emulate_media`——模拟 screen/print、深浅色主题，测试响应式与打印样式 |
| 🌐 **打开任意网页** | 真实 Chromium 渲染，JS/CSS 完整执行，不是「抓源码」 |
| 👀 **阅读页面内容** | 无障碍树快照，结构化输出，AI 可直接理解页面 |
| 🖱️ **像人一样操作** | 点击、输入、填表、下拉选择、拖拽、悬停、滚动 |
| 📸 **截图取证** | 任意时刻保存页面截图，可见即可得 |
| 🕵️ **深度调试** | 网络请求抓包、console 日志、文件上传、多标签页 |
| 🤖 **执行脚本** | 页面内运行 JavaScript，突破常规操作的边界 |

## 效果演示

下图是在真实设备（Android + proot arm64）上，由 AI 自动完成「打开网页 → 等待渲染 → 截图」的百度首页：

![demo](assets/demo.png)

## 快速开始

### 方式零：从 Operit 市场安装（条目审核中，暂可能搜不到）

在 Operit 内打开插件市场 → 搜索 **Playwright MCP** → 安装 → 重启 MCP 服务即可。

⚠️ 市场条目目前**仍在审核**，可能搜索不到。**搜不到请直接使用下面的「方式一」**，两者安装结果完全一致。

插件采用**自举设计**：包内只带声明文件（`package.json` / `requirements.txt` / 转发器），依赖与 Chromium 在首次启动时由转发器自动补齐，因此市场包很小、也能做到装完即用。

### 方式一：一键脚本（最推荐）
**A. 从 Release 下载完整包（国内推荐，无需访问 raw.githubusercontent.com）**

1. 打开 [Releases](https://github.com/x15907982411/playwright-mcp-for-operit/releases/latest)，下载 `playwright-mcp-for-operit-v1.0.7.zip`
2. 解压后进入目录执行：

```bash
unzip playwright-mcp-for-operit-v1.0.7.zip
cd playwright-mcp-for-operit-v1.0.7
bash install.sh            # 自动完成：环境检查 → 依赖安装 → Chromium 探测 → 配置生成 → 双路径部署 → venv
```

**B. 只下载 install.sh（需要能访问 raw.githubusercontent.com）**

```bash
curl -sL https://raw.githubusercontent.com/x15907982411/playwright-mcp-for-operit/main/install.sh -o install.sh
bash install.sh
```

> 💡 B 方案单独下载脚本时，脚本会自动从 GitHub API 补齐 `scripts/playwright_mcp.py`；
> 若本机连 api.github.com 也访问不了，请改用 A 方案（完整包无需联网拉任何脚本）。

**可选参数：**

```bash
bash install.sh --global       # 依赖装到全局 node_modules
bash install.sh --skip-deps    # 跳过依赖安装，交给自举转发器首次启动时处理
bash install.sh --keep-deps    # 重跑时保留已有 node_modules（不重装依赖）
bash install.sh --dry-run      # 只检查、不写文件
bash install.sh --help         # 显示完整帮助
```

完成后在 Operit 中重启 MCP 服务，`ping_mcp(playwright_mcp)` 能看到 **25 个 `browser_*` 工具**即可使用。

> 💡 脚本先保存到本地再执行（非 `curl | bash` 管道），建议运行前先 `cat install.sh` 浏览一遍。
>
> 💡 **推荐在 proot 环境执行**：Termux 与 proot 的 `~/.cache` 不互通，双环境切换会重复下载 Chromium。
>
> ⚠️ **npm 源提示**：`@playwright/mcp@0.0.82` 依赖的 `playwright-core@1.64.0-alpha-*` 为 alpha 版本，
> 国内镜像 `registry.npmmirror.com` **可能尚未同步**；若 `npm install` 报 `ETARGET`，请用官方源：
> `npm install --registry https://registry.npmjs.org`
>
> 🗑 卸载：`bash uninstall.sh`（支持 `--keep-files` / `--purge` / `--dry-run`）。

### 方式二：手动部署（概览）

需要自行控制每一步时，按以下顺序操作：

1. 准备插件目录（`playwright_mcp.py` 转发器 + `requirements.txt` + `package.json` + `mcp.config.json`）
2. 安装 Node 依赖：`npm install`（**在 Linux 运行目录内**，读 `package.json`）——也可跳过，交给首次启动自举
3. 写入 `mcp_config.json`（使用仓库全字段模板，勿手写精简片段）
4. 双路径部署（Android 源目录 + Linux 运行目录 `~/mcp_plugins/`）+ 准备 `venv`
5. 重启 MCP 并验证（`ping_mcp` → 25 个工具）

> 📖 每步的完整命令、配置注释与回滚方式，见 **[docs/DEPLOY.md](docs/DEPLOY.md)**。

## 首次启动会发生什么

无论用哪种方式安装，首次启动 MCP 时转发器都会自动兜底：

1. 找不到 `@playwright/mcp` → 自动 `npm install`（插件目录本地优先，回退全局）；
2. 找不到 Chromium → 先复用本机已有的（`~/.cache/ms-playwright`），实在没有才下载（约 150MB，数分钟）；
3. 全程日志写在 `~/mcp_plugins/playwright_mcp/bootstrap.log`。

> 💡 若首次启动因下载超时失败，**再重启一次 MCP 即可**（包与浏览器已就位）。
>
> 💡 可用 `PW_MCP_AUTO_INSTALL=0` / `PW_MCP_AUTO_DOWNLOAD=0` 关闭自动行为（在 `mcpServers.playwright_mcp.env` 里设）。
> 💡 本机存在多个 chromium build 时，可用 `PW_MCP_PREFERRED_BUILD`（默认 `1237`）指定优先版本；详见 [TROUBLESHOOTING 问题 13](docs/TROUBLESHOOTING.md#chromium-sigtrap)。

## 使用示例

激活后，AI 可以像这样完成一个完整任务：

```js
use_package playwright_mcp

browser_navigate("https://www.baidu.com")     // 打开百度
browser_snapshot()                            // 读取页面结构
browser_type(target: "e36", text: "Operit")   // 搜索框输入
browser_click(target: "e63")                  // 点击「百度一下」
browser_take_screenshot()                     // 截图留证
```

整个过程是 **打开 → 理解 → 操作 → 验证** 的闭环，每一步都有结构化反馈（页面标题、无障碍树、网络日志），AI 可据此自主判断、纠错、继续。

## 常见问题

| 问题 | 答案 |
|---|---|
| **手机内存够吗？** | Chromium headless 约占 300–500MB，建议可用内存 ≥ 1GB（实测 8 核 + 1GB 环境运行流畅） |
| **市场装完重启后第一次很慢 / 失败？** | 正常：首次启动要装 MCP 包 + 准备 Chromium（可能下载 150MB）。**再重启一次 MCP** 即可；进度与错误见 `bootstrap.log` |
| **重启 MCP 报 Unknown error，但插件其实起来了？** | 已知现象：Operit 的重启工具有时会报错，但插件已成功加载。以 `ping_mcp` 能否列出 25 个工具为准 |
| **`ping_mcp` 工具数对不对？** | 官方 `@playwright/mcp` **v0.0.82 实际是 25 个**。v1.0.0~v1.0.5 文档写「24」是**漏列了 `browser_emulate_media`**，v1.0.6 起已修正 |
| **插件加载不上 / 报 Unknown error？** | 多为 `pluginMetadata` 字段不完整（缺 `updatedAt` 会触发 Operit 空指针）。请用 v1.0.6 的 `install.sh` 或 `config/mcp_config.json`，**不要手写精简片段** |
| **会被网站风控吗？** | 无头浏览器访问少数风控严格的站点（如百度搜索）可能触发验证码，属所有自动化方案的通病；可用真实 UA 或带登录态 cookie 缓解 |
| **和 Operit 内置 browser 包有何区别？** | 内置包在部分设备有内核兼容问题（页面无法加载）；本方案基于官方 MCP server + 完整 Chromium，实测全链路可用，且多出网络抓包、console 日志等能力 |

> 更多问题（apt 404、Chromium 镜像缺失、依赖库、截图落盘位置等）见 **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**。

## 文档导航

| 文档 | 内容 |
|---|---|
| [install.sh](install.sh) | 一键安装脚本（支持 `--global` / `--skip-deps` / `--dry-run`） |
| [uninstall.sh](uninstall.sh) | 卸载脚本（支持 `--keep-files` / `--purge` / `--dry-run`） |
| [docs/DEPLOY.md](docs/DEPLOY.md) | 手动部署完整流程、配置注释、回滚 |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | 故障排查（含首次启动自举、镜像缺失、依赖库等） |
| [market/README.md](market/README.md) | **发布到市场的机制说明与配置规范**（含自动安装行为） |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 报告 Bug / 提交 PR |
| [CHANGELOG.md](CHANGELOG.md) | **版本更新记录**（含插件版本与上游 MCP 版本解耦说明） |
| [SECURITY.md](SECURITY.md) | 漏洞报告流程 |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | 行为准则 |

## 相关链接

- 上游 MCP server：[microsoft/playwright-mcp](https://github.com/microsoft/playwright-mcp)（v0.0.82，**Apache-2.0**）
- 运行平台：[AAswordman/Operit](https://github.com/AAswordman/Operit)
- 浏览器内核：Chromium（arm64 headless）

## License

- **本项目**（部署脚本 / 配置模板 / 文档）：**MIT**，详见 [LICENSE](LICENSE)
- **上游 MCP server**：[Microsoft Playwright MCP](https://github.com/microsoft/playwright-mcp) 为 **Apache-2.0**，安装时通过 npm 获取（`@playwright/mcp@0.0.82`），版权归 Microsoft 所有。本仓库**不包含**上游源代码
- **商标**：Playwright 是 Microsoft 的商标。本项目为独立社区适配项目，与 Microsoft 无隶属关系；项目名中引用「Playwright」仅用于描述兼容性
