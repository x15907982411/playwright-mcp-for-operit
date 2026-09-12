# 贡献指南（CONTRIBUTING.md）

感谢你对 **Playwright MCP for Operit** 感兴趣！

本项目为 [Operit](https://github.com/AAswordman/Operit)（Android AI 助手）适配官方 [Playwright MCP](https://github.com/microsoft/playwright-mcp)，让 AI 拥有真正的浏览器能力。

## 目录

- [报告 Bug](#-报告-bug)
- [提交功能建议](#-提交功能建议)
- [提交代码（PR）](#-提交代码pr)
- [发布流程（维护者）](#-发布流程维护者)
- [License](#-license)

---

## 🐛 报告 Bug

请先搜索 [Issues](https://github.com/x15907982411/playwright-mcp-for-operit/issues) 确认没有重复，然后使用 **Bug Report 模板**创建，并尽量包含：

1. **环境**：设备型号、Android 版本、proot/Termux 环境、node 版本（`node -v`）
2. **复现步骤**：安装方式（市场 / 一键脚本 / 手动）、报错输出（请贴 `tail -20` 的完整日志）
3. **自举日志**：`tail -30 ~/mcp_plugins/playwright_mcp/bootstrap.log`
4. **期望行为 vs 实际行为**
5. 截图或日志文件（敏感信息请打码）

> 💡 部署类问题优先自查：[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) 覆盖了自举慢、venv 缺失、镜像 404、NPE 等常见坑。

## 💡 提交功能建议

使用 **Feature Request 模板**，说明：

- 想解决的问题（而不是直接给方案）
- 使用场景
- 可选的实现思路

## 🔧 提交代码（PR）

1. Fork 本仓库，从 `main` 新建分支：`git checkout -b feature/xxx`
2. 遵循项目风格：
   - `install.sh` / `uninstall.sh`：`set -eu`（**不要加 `pipefail`**，`cmd | head -1` 的 SIGPIPE 会误杀脚本）、错误显式退出并给出可操作提示、幂等设计（可重复执行）、备份用户配置
   - **npm install 只能跑在 Linux 文件系统内**（`/sdcard` 是 FUSE，不支持文件锁/符号链接）
   - 转发器 `scripts/playwright_mcp.py`：只使用标准库，保持自举能力（缺依赖要能自己补）
   - 配置模板：`pluginMetadata` 必须保持 15 字段全量（缺 `updatedAt` 会触发 Operit NPE）
3. 本地验证：
   - `bash -n install.sh && bash -n uninstall.sh`
   - `python3 -m py_compile scripts/playwright_mcp.py`
   - 在干净目录里仅放包内文件，跑一次转发器确认自举链路可用
4. 提交 PR，使用 PR 模板填写，描述改动与测试情况

## 🚀 发布流程（维护者）

版本号语义：`v1.0.x` 递增（脚本/文档改动即递增）。发布步骤：

1. 更新以下四处版本号（保持一致）：
   - `package.json` 的 `version`
   - `config/mcp_config.json` 的 `pluginMetadata.playwright_mcp.version`
   - `install.sh` / `uninstall.sh` 头部注释
   - `README.md` 徽章
2. 推送 main → 打 tag → 创建 Release（附 zip 资产）
3. 在 Operit 发布页面登记市场（参阅 [market/README.md](market/README.md)）

> ⚠️ 市场登记版本必须**大于当前已有版本**（曾遇 409 `version_conflict`）。

## 📄 License

MIT — 提交代码即表示同意以 MIT 协议授权你的贡献。
