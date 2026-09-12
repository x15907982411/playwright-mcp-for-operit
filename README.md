# Playwright MCP for Operit

[![version](https://img.shields.io/badge/version-1.0.4-4A90D9?style=flat-square)](https://github.com/x15907982411/playwright-mcp-for-operit)
[![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-Android%20%2B%20proot%20arm64-blueviolet?style=flat-square)](#环境要求)
[![tools](https://img.shields.io/badge/browser__tools-24-orange?style=flat-square)](#它能做什么)
[![upstream](https://img.shields.io/badge/upstream-%40playwright%2Fmcp%400.0.80-black?style=flat-square)](https://github.com/microsoft/playwright-mcp)

> **为 Operit 装上真正的浏览器。**
>
> 让你的 AI 助手自己打开网页、阅读内容、搜索填表、截图取证——一切自动化，全程可观测。

本项目将微软官方的 [Playwright MCP](https://github.com/microsoft/playwright-mcp)（v0.0.80）接入 [Operit](https://github.com/AAswordman/Operit)（Android 上的 AI 助手）。基于 Chromium 内核，在手机上获得与桌面浏览器一致的渲染与交互能力。

---

## 目录

- [环境要求](#环境要求)
- [它能做什么](#它能做什么)
- [效果演示](#效果演示)
- [快速开始](#快速开始)
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
| **Node.js** | ≥ 18（实测 v24） | 用于启动 MCP server |
| **可用内存** | ≥ 1GB | Chromium headless 约占 300–500MB |
| **磁盘空间** | ~150MB（仅在需下载 Chromium 时） | 已有 Chromium 则零下载 |

## 它能做什么

**24 个 `browser_*` 工具**，覆盖「打开 → 操作 → 取证」完整链路，工具面与官方 Playwright MCP v0.0.80 完全一致。

| 能力 | 说明 |
|---|---|
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

### 方式一：一键脚本（推荐）

```bash
# 下载并运行（自动完成：环境检查 → 安装 MCP → 定位/下载 Chromium → 生成配置 → 双路径部署）
curl -sL https://raw.githubusercontent.com/x15907982411/playwright-mcp-for-operit/main/install.sh -o install.sh
bash install.sh
```

完成后在 Operit 中重启 MCP 服务，`ping_mcp(playwright_mcp)` 能看到 **24 个 `browser_*` 工具**即可使用。

> ⚠️ `raw.githubusercontent.com` 在国内可能无法直连，可从 [Release v1.0.4](https://github.com/x15907982411/playwright-mcp-for-operit/releases) 的 zip 中提取 `install.sh`。
>
> 💡 脚本先保存到本地再执行（非 `curl | bash` 管道），建议运行前先 `cat install.sh` 浏览一遍。
>
> 💡 **推荐在 proot 环境执行**：Termux 与 proot 的 `~/.cache` 不互通，双环境切换会重复下载 Chromium。

### 方式二：手动部署（概览）

需要自行控制每一步时，按以下顺序操作：

1. 安装 `@playwright/mcp@0.0.80`（**必须锁版本**）
2. 准备 Chromium（**优先复用**已有，避免 arm64 镜像 404）
3. 写入 `mcp_config.json`（使用仓库全字段模板，勿手写精简片段）
4. 双路径部署（Android 源目录 + Linux 运行目录）
5. 重启 MCP 并验证（`ping_mcp` → 24 个工具）

> 📖 每步的完整命令、配置注释与回滚方式，见 **[docs/DEPLOY.md](docs/DEPLOY.md)**。

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
| **`ping_mcp` 只有 24 个工具，不是 25 个？** | **24 个是正确的**。官方 v0.0.80 就是 24 个；早期文档（v1.0.0）写「25」是笔误，v1.0.1 起已修正 |
| **插件加载不上 / 报 Unknown error？** | 多为 `pluginMetadata` 字段不完整（缺 `updatedAt` 会触发 Operit 空指针）。请用 v1.0.4 的 `install.sh` 或 `config/mcp_config.json`，**不要手写精简片段** |
| **会被网站风控吗？** | 无头浏览器访问少数风控严格的站点（如百度搜索）可能触发验证码，属所有自动化方案的通病；可用真实 UA 或带登录态 cookie 缓解 |
| **和 Operit 内置 browser 包有何区别？** | 内置包在部分设备有内核兼容问题（页面无法加载）；本方案基于官方 MCP server + 完整 Chromium，实测全链路可用，且多出网络抓包、console 日志等能力 |

> 更多问题（apt 404、Chromium 镜像缺失、依赖库、截图落盘位置等）见 **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**。

## 文档导航

| 文档 | 内容 |
|---|---|
| [docs/DEPLOY.md](docs/DEPLOY.md) | 手动部署完整流程、配置注释、回滚 |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | 故障排查（8 个常见问题，含根因与修复） |
| [install.sh](install.sh) | 一键安装脚本 |
| [market/README.md](market/README.md) | 发布到 Operit 市场的配置规范 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 报告 Bug / 提交 PR |
| [SECURITY.md](SECURITY.md) | 漏洞报告流程 |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | 行为准则 |

## 相关链接

- 上游 MCP server：[microsoft/playwright-mcp](https://github.com/microsoft/playwright-mcp)（v0.0.80，**Apache-2.0**）
- 运行平台：[AAswordman/Operit](https://github.com/AAswordman/Operit)
- 浏览器内核：Chromium（arm64 headless）

## License

- **本项目**（部署脚本 / 配置模板 / 文档）：**MIT**，详见 [LICENSE](LICENSE)
- **上游 MCP server**：[Microsoft Playwright MCP](https://github.com/microsoft/playwright-mcp) 为 **Apache-2.0**，安装时通过 npm 获取（`@playwright/mcp@0.0.80`），版权归 Microsoft 所有。本仓库**不包含**上游源代码
- **商标**：Playwright 是 Microsoft 的商标。本项目为独立社区适配项目，与 Microsoft 无隶属关系；项目名中引用「Playwright」仅用于描述兼容性
