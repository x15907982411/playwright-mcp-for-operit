# Changelog

本插件遵循 [语义化版本](https://semver.org/lang/zh-CN/)，但请注意：**插件自身版本与上游 `@playwright/mcp` 版本是两条独立的版本线**。

## [1.0.9] - 2026-11-01

### 跟上上游 0.0.84

`@playwright/mcp` 从 0.0.83 升到 0.0.84，`playwright-core` 跟着从 `1.64.0-alpha-1790635538000` 走到 `1.65.0-alpha-2026-10-30`。

这次上游动的东西不算多，但对实际用起来挺有帮助：

- `browser_tabs` 加了 `isolatedContext`。传个名字进去就开一个独立的浏览器上下文，cookie 和 localStorage 都是分开的。以前想同时挂两个账号，得反复退登录清缓存，现在开两个 context 就互不干扰
- `browser_find` 加了 `maxResults`。之前页面上有几十个匹配项会全吐出来，现在能限个数，只找一个元素的时候省不少 token
- `browser_network_requests` 加了 `all`。以前页面一跳转，之前的请求记录就没了；现在打开这个开关能拿到整段会话的请求，排查接口问题方便些
- 新增启动参数 `--redact-url-params=access_token,code`，URL 里的敏感参数会被打码，免得 token 混进日志。这只是图个方便，别当成安全边界——真不该露的东西，本来就不该出现在 URL 里
- `target` 的写法也放宽了，JS、Python、Java、C# 四种风格的定位器都能认
- 新增 `--ignore-roots`：客户端声明了 workspace roots 但没法响应 `roots/list` 时，可以忽略这项检查

### Chromium 还是用 1237

上游 0.0.84 配套的 Chromium 是 1252（Chrome 157.0.8103.15），比 0.0.83 那会儿的 1247 又往前跳了 5 个。

但之前踩过坑：proot 环境里 rev1246 以上的 build 一启动就是 SIGTRAP（exit 133），根本起不来。所以 1237 继续留着用。

这次特意试了跨版本能不能跑——playwright 1.65 跟 Chromium 1237 差了 15 个 build，实测启动、渲染、截图、执行 JS 都正常，没报错。`PW_MCP_KNOWN_BAD_MIN=1246` 的拦截逻辑原样保留，自动下载万一跑到新 build 上还能拦住。

### 在 W200DS 上试了一遍

- `npm install @playwright/mcp@0.0.84` 只更新了三个包（mcp、playwright、playwright-core），4 秒左右完成，Chromium 不用重下
- 版本核对：mcp 0.0.84 / playwright 1.65.0-alpha-2026-10-30 / playwright-core 1.65.0-alpha-2026-10-30
- Chromium 冷启动 0.6 秒，机器忙的时候大概 3 秒，报出来的浏览器版本是 152.0.7977.8
- 打开页面、截图、取 DOM 内容、跑 JS 都正常，跟升级前没区别
- 新参数试了两个：`browser_find(maxResults=1)` 只回一条，输出里写着 showing first 1；`browser_tabs(isolatedContext="test-ctx")` 建出来的 tab 会标注 `[isolatedContext: test-ctx]`
- 工具数量还是 25 个，跟 0.0.83 一样

### 升级时注意

- 转发器里的 `MCP_VER` 默认值同步成 0.0.84 了。如果只升 npm 包不改转发器，启动时版本校验会发现对不上，然后自动把包装回 0.0.83，看起来就像“升级没生效”，其实是自愈逻辑在干活
- 全局目录里留着的旧版（比如 `/usr/lib/node_modules` 下的 0.0.80）不影响使用，转发器优先用插件目录里的那份

### 顺手把安装脚本的几处毛病理了理

这版除了跟上游，`install.sh` 里几个长期存在的问题也一起处理了。跟 0.0.84 没关系，是之前就有的：

- **结构校验失败却报成功**：以前只打一句「存在校验项失败」就继续往下走，最后照样打印「✅ 部署完成」。现在会直接报错退出，退出码非 0，自动化调用能正确判断
- **`--keep-deps` 不查版本**：以前不管现有依赖是什么版本都原样保留。从 0.0.83 升上来还带这个参数的话，会留下旧包，转发器启动时的版本校验又要把包装回去，白绕一圈。现在先查实际版本，对不上就走常规安装并明确提示
- **备份名同秒覆盖**：主配置备份以前精确到秒，同一秒连跑两次会互相覆盖。现在文件名带上了进程号
- **主配置非原子写入**：以前直接覆盖原文件，中途被杀掉或断电可能留下半截 JSON。现在先写临时文件再重命名，不会出现半个文件
- **参数写错误装**：命令行参数打错时，以前只提示「未知参数，已忽略」然后照常安装。现在直接拒绝、打印用法并退出（码 2）
- **非法 `PW_MCP_INSTALL_MODE`**：以前会被静默当成 `local`，现在明确报错
- **小加固两处**：Chromium 探测加上了可执行权限过滤；npm 安装前会先检查运行目录是否可写

### 插件 ID 统一成 playwrightmcp

这是个历史遗留问题：仓库里部署脚本用的 ID 是 `playwright_mcp`（带下划线），但 Operit 市场装出来和实机运行的目录都是 `playwrightmcp`（不带下划线）。

结果就是：手动跑 `install.sh` 会装出另一个 ID 的插件，跟市场版并存出现在列表里，用户不知道该用哪个；而且会把新版文件放到没人读取的目录，看起来像「升级了没生效」。

这版统一改成 `playwrightmcp`，转发器文件也跟着从 `scripts/playwright_mcp.py` 改名为 `scripts/playwrightmcp.py`，仓库里 14 个文件共 124 处引用一起对齐。

装过旧 ID 的人升级时，安装脚本会把 `mcpServers` 和 `pluginMetadata` 里的旧条目一并清掉，不会出现新旧两个条目同时被加载；卸载脚本也会两个 ID 都清。旧运行目录（`~/mcp_plugins/playwright_mcp`）不自动删，装的时候提示一句，确认没用了自己删就行。这条迁移路径也补了回归测试。


## [1.0.8] - 2026-09-30
### ⬆️ 上游同步
- 适配 `@playwright/mcp` **0.0.82 → 0.0.83**（上游 8 项 bugfix：`browser_find` 正则/文件名支持、navigate/reload 遇对话框报错、下载中关闭浏览器防崩、`wait_for` 超时明示、WebMCP 陈旧标签绑定、snapshot 正则名加引号等）
- `playwright-core` 同步 `1.64.0-alpha-1790635538000`
### 🔒 兼容性（决策保持不变）
- 新增 `PW_MCP_KNOWN_BAD_MIN`（默认 1246）：最终选中的 Chromium build >= 此值（且 != 1237）时**拒绝启动**（防 proot SIGTRAP；自动下载路径同样拦截；`PW_MCP_PREFERRED_BUILD=0` 时依旧生效）
- **Chromium build 偏好继续钉 1237**：上游 0.0.83 官方配套为 1247，但 proot 下 rev1246+ 启动即 SIGTRAP；1237 在旧/新驱动下均实测兼容，跨 build 复用策略不变（`PW_MCP_MIN_BUILD` / `PW_MCP_PREFERRED_BUILD` 保持 1237）
### ✅ 本机验证
- 全链路实测：npm 升级 → 重启 MCP → 25 工具在线 → navigate / snapshot / screenshot / wait_for / close 全通过

## [1.0.7] - 2026-09-23

### 🐛 修复（来自社区反馈）
- **「自动下载 Chromium」必然失败**：`install chromium` → **`install-browser chromium`**。
  `@playwright/mcp@0.0.82` 的 cli.js 只把 `install-browser` 映射给下游 Playwright，
  直接传 `install chromium` 会被顶层解析器拒掉（`too many arguments: install, chromium`）。
  受影响共 5 处：转发器下载调用、docstring、两处提示文本、DEPLOY 表格。
  ※ 本机已有 Chromium 的环境永远不会走到这条路径，属长期潜伏 bug —— 感谢 @bingfengcxl-crypto 报告（#4）

### 🛡️ 兼容性
- 新增排障条目 [问题 13](docs/TROUBLESHOOTING.md)：**proot 下新版 Chromium（rev1246+）启动即 SIGTRAP**
  （exit 133 / GPU process exit_code=5），并给出 chromium-1237 的回退与下载命令 —— 感谢 @bingfengcxl-crypto 报告（#5）
- 转发器新增 **`PW_MCP_PREFERRED_BUILD`**（默认 `1237`）：本机存在多个 build 时优先选已知可用版本，
  不再「选最新」（新版在 proot 下会崩）
- `PW_MCP_MIN_BUILD` 默认值 **1243 → 1237**（原值会让 1237 白刷一条 WARN；`install.sh` 同步）

### 📄 文档
- DEPLOY：Chromium 行补 `install-browser` 与 build 偏好说明；环境变量表补 `PW_MCP_PREFERRED_BUILD`

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
