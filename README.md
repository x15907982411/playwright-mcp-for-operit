# Playwright MCP for Operit

[![version](https://img.shields.io/badge/version-1.0.0-4A90D9?style=flat-square)](https://github.com/x15907982411/playwright-mcp-for-operit)
[![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

> **为 Operit 装上真正的浏览器。**
> 让你的 AI 助手自己打开网页、阅读内容、搜索填表、截图取证——一切自动化，全程可观测。

Playwright MCP for Operit 将微软官方的 [Playwright MCP](https://github.com/microsoft/playwright-mcp) 无缝接入 [Operit](https://github.com/AAswordman/Operit)（Android 上的 AI 助手）。基于 Chromium 内核，在手机上获得与桌面浏览器完全一致的渲染与交互能力。

---

## ✨ 它能做什么

| | 能力 | 说明 |
|---|---|---|
| 🌐 | **打开任意网页** | 真实 Chromium 渲染，JS/CSS 完整执行，不是"抓源码" |
| 👀 | **阅读页面内容** | 无障碍树快照，结构化输出，AI 可直接理解页面 |
| 🖱 | **像人一样操作** | 点击、输入、填表、下拉选择、拖拽、悬停、滚动 |
| 📸 | **截图取证** | 任意时刻保存页面截图，可见即可得 |
| 🕵️ | **深度调试** | 网络请求抓包、console 日志、文件上传、多标签页 |
| 🤖 | **执行脚本** | 页面内运行 JavaScript，突破常规操作的边界 |

**25 个工具**覆盖从打开到操作到取证的完整链路，工具面与官方 Playwright MCP 完全一致。

## 🖼 效果演示

下图是 Playwright MCP for Operit 在真实设备（Android + proot arm64）上打开的百度首页截图——由 AI 自动完成"打开网页 → 等待渲染 → 截图"：

![demo](assets/demo.png)

## 🚀 快速开始（3 分钟）

```bash
# 1. 在 proot 环境安装（需 node ≥ 18）
npm i -g @playwright/mcp
npx playwright install-deps chromium

# 2. 把 config/mcp_config.json 中的 playwright_mcp 条目
#    合并进 Operit 的 /sdcard/Download/Operit/mcp_plugins/mcp_config.json

# 3. 双路径部署（Android 源目录 + Linux 运行目录）
mkdir -p /sdcard/Download/Operit/mcp_plugins/playwright_mcp
cp config/mcp_config.json /sdcard/Download/Operit/mcp_plugins/playwright_mcp/
cp -r /sdcard/Download/Operit/mcp_plugins/playwright_mcp /root/mcp_plugins/
```

然后在 Operit 中重启 MCP 服务，`ping_mcp(playwright_mcp)` 能看到 25 个 `browser_*` 工具，就完成了 🎉。

> 💡 不需要下载浏览器：脚本会自动复用设备上已有的 Chromium；没有则自动下载（约 150MB，一次性）。

## 📖 使用示例

激活后，AI 可以像这样完成一个完整任务：

```text
use_package playwright_mcp

→ browser_navigate("https://www.baidu.com")     # 打开百度
→ browser_snapshot()                             # 读取页面结构
→ browser_type(target: "e36", text: "Operit")    # 搜索框输入
→ browser_click(target: "e63")                   # 点击"百度一下"
→ browser_take_screenshot()                      # 截图留证
```

整个过程：**打开 → 理解 → 操作 → 验证**，每一步都有结构化反馈（页面标题、无障碍树、网络日志），AI 可以据此自主判断、纠错、继续。

## ❓ 常见问题

**Q：手机内存够吗？**
Chromium headless 约占用 300-500MB 内存，建议可用内存 ≥ 1GB（实测 8 核 + 1G 内存环境运行流畅）。

**Q：会被网站风控吗？**
无头浏览器访问少数风控严格的站点（如百度搜索）可能触发验证码——这是所有自动化方案的通病，换 UA 或带登录态 cookie 即可缓解。

**Q：和 Operit 内置 browser 包有什么区别？**
内置包在部分设备存在内核兼容问题（页面无法加载）；本方案基于官方 MCP server + 完整 Chromium，实测全链路可用，且多出网络抓包、console 日志等能力。

## 📚 更多文档

- [部署手册（DEPLOY.md）](docs/DEPLOY.md) — 手动部署、配置注释、回滚
- [故障排查（TROUBLESHOOTING.md）](docs/TROUBLESHOOTING.md) — 常见问题与解决
- [安装脚本（install.sh）](install.sh) — 一键部署

## 🔗 相关链接

- 上游 MCP server：[microsoft/playwright-mcp](https://github.com/microsoft/playwright-mcp)
- 运行平台：[AAswordman/Operit](https://github.com/AAswordman/Operit)
- 浏览器内核：Chromium（arm64 headless）

## License

MIT — 本项目包含部署脚本与文档；MCP server 版权归 [Microsoft Playwright MCP](https://github.com/microsoft/playwright-mcp) 所有。
