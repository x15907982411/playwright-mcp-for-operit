# Changelog

本插件遵循 [语义化版本](https://semver.org/lang/zh-CN/)，但请注意：**插件自身版本与上游 `@playwright/mcp` 版本是两条独立的版本线**。

## [1.0.6] - 2026-09-19

### ⬆️ 上游跟进
- `@playwright/mcp` **0.0.80 → 0.0.82**
- 工具数订正：**24 → 25**（v1.0.0 ~ v1.0.5 文档漏列了 `browser_emulate_media`，实测 `tools/list` 一直是 25）
- 上游新特性：60fps 可样式化视频录制（`browser_start_video`，devtools opt-in）、WebMCP 工具、`--profile-dir-name`

### 🔧 install.sh
- `--keep-deps` 真正生效（此前会先 `rm -rf` 整个运行目录再谈"保留依赖"）
- 默认改用 **npm 官方源**（0.0.82 依赖 `playwright-core@1.64.0-alpha-*`，国内镜像未同步会报 `ETARGET`）
- 转发器下载：`.tmp` → 校验 → 原子替换（不再可能留半成品）
- 配置合并加类型校验（`mcpServers` / `pluginMetadata` 非对象时重置并告警，不静默）
- 主配置备份失败时明确中止；备份上限 5 份
- `uninstall.sh` 去掉 `eval`（消除字符串逃逸面）
- **patch 1**：`pluginMetadata.version` 改用**插件自身版本**（此前误用上游 MCP 版本 `0.0.82`）
- **patch 3**：`KEEP_DEPS_EFFECTIVE` 提升到全局初始化区 —— 修掉 `--dry-run` 下 `set -u` 的 `unbound variable` 崩溃
- **patch 3**：备份清理改用便携写法 `ls -1t`（原 `find -printf` 属 GNU 扩展，Termux 的 toybox `find` 不支持）
- **patch 3**：python3 缺失时，转发器下载校验自动降级为「shebang + 体积下限」，不再 100% 失败
- **patch 3**：`--keep-deps` 的文件复制循环由 `[ -f ] && cp` 改为 `if`，消除 `set -e` 返回值传染

### 🐍 转发器（scripts/playwright_mcp.py）
- 新增 node 版本校验（< 18 或解析失败则跳过该候选，日志可见）
- `bootstrap.log` 日志轮转（超 1MB 转 `.log.1`；`PW_MCP_LOG_MAX` 可调）
- **patch 3**：新增 `_int_env()` —— 非法整型环境变量（如 `PW_MCP_LOG_MAX=1m`）只告警并回退默认值，**不再 ValueError 崩溃**
- **patch 3**：`run()` 增加 `cwd` 参数；本地 `npm install` 显式传 `cwd=HERE`（不再隐式依赖进程 cwd）

### 📌 版本语义变更（升级必读）
- 自 **1.0.6** 起，`pluginMetadata.version` 表示**插件自身版本**（`1.0.6`），与上游 `@playwright/mcp` 版本（`0.0.82`）**解耦**
- 从旧版升级后，Operit 插件页显示的版本会由 `0.0.x` 变为 `1.0.6` —— **这是预期行为**，仅元数据变化，功能不受影响

### ✅ 验证记录
- **三轮代码审查**（作者自审 → 陌生视角 → 外部 AI → 作者终审），累计修复 **28 项**
- 实测覆盖：隔离安装 / 重复安装（幂等）/ `--dry-run` / `--dry-run --keep-deps` / `--keep-deps` / `uninstall` / 非法环境变量容错 / 备份上限清理
- 端到端：MCP 握手成功，`tools/list` 返回 **25** 个工具；Chromium 复用 `chromium-1237`（跨驱动兼容，无需重下）

## [1.0.5] 及更早
历史版本见 [Releases](https://github.com/x15907982411/playwright-mcp-for-operit/releases)。
