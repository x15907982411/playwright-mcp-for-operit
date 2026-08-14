# 贡献指南（Contributing）

感谢你对 **Playwright MCP for Operit** 感兴趣！本项目为 [Operit](https://github.com/AAswordman/Operit)（Android AI 助手）适配官方 [Playwright MCP](https://github.com/microsoft/playwright-mcp)，让 AI 拥有真正的浏览器能力。

## 🐛 报告 Bug

请先搜索 [Issues](https://github.com/x15907982411/playwright-mcp-for-operit/issues) 确认没有重复，然后使用 **Bug Report 模板**创建，并尽量包含：

1. **环境**：设备型号、Android 版本、proot/Termux 环境、node 版本（`node -v`）
2. **复现步骤**：安装方式（一键脚本/手动）、报错输出（请贴 `tail -20` 的完整日志）
3. **期望行为 vs 实际行为**
4. 截图或日志文件（敏感信息请打码）

> 💡 部署类问题优先自查：`docs/TROUBLESHOOTING.md` 覆盖了镜像缺失、NPE、依赖缺失等常见坑。

## 💡 提交功能建议

使用 **Feature Request 模板**，说明：

- 想解决的问题（而不是直接给方案）
- 使用场景
- 可选的实现思路

## 🔧 提交代码（PR）

1. Fork 本仓库，从 `main` 新建分支：`git checkout -b feature/xxx`
2. 遵循项目风格：
   - `install.sh`：保持 `set -e`、错误显式退出并给出可操作提示、幂等设计（可重复执行）、备份用户配置
   - README/文档：中文为主，踩坑内容下沉到 `docs/`
   - 配置模板：`pluginMetadata` 必须保持 15 字段全量（缺 `updatedAt` 会触发 Operit NPE）
3. 本地验证：`bash -n install.sh` 语法检查 + 条件允许时完整跑一遍安装脚本
4. 提交 PR，使用 PR 模板填写，描述改动与测试情况

## 🚀 发布流程（维护者）

版本号语义：v1.0.x 递增（脚本/文档改动即递增）。发布步骤：

1. 更新 `install.sh` 头部版本号 + README 徽章/FAQ 中的版本引用
2. 推送 main → 打 tag → 创建 Release（附 zip 资产）
3. （可选）同步 Operit 市场条目版本号

## 📄 License

MIT — 提交代码即表示同意以 MIT 协议授权你的贡献。