# 发布到 Operit 市场

本目录包含发布到 Operit 插件市场所需的配置模板与说明。

## 目录

- [核心机制：市场安装到底自动做了什么](#核心机制市场安装到底自动做了什么)
- [两条发布路线](#两条发布路线)
- [配置 JSON 字段规范](#配置-json-字段规范)
- [本插件（Playwright MCP）的推荐配置](#本插件playwright-mcp的推荐配置)
- [发布前自检清单](#发布前自检清单)
- [常见坑](#常见坑)

---

## 核心机制：市场安装到底自动做了什么

> 以下行为从 Operit 应用内部实现提取（安装命令字符串实测），决定了你的插件能不能做到「一键可用」。

安装一个本地（stdio）插件时，Operit 会将 Android 侧插件目录复制到 Linux 侧 `~/mcp_plugins/<server_id>/`，并**根据包内文件自动准备依赖**：

| 包内文件 | Operit 自动执行 | 实际效果 |
|---|---|---|
| `package.json` | `npm install` / `pnpm install` | Node 依赖装到**插件目录内的** `node_modules` |
| `requirements.txt` | `pip install -r requirements.txt`（venv） | Python 依赖装到插件目录内的 `venv` |
| `command` 写 `npx` / `uvx` | 转 `pnpm dlx` / `uvx` 执行 | 边跑边拉包 |

两个关键限制：

1. **安装命令带 `--ignore-scripts`** —— 所以**不能依赖 npm `postinstall`** 去跑额外步骤（比如下载浏览器）。
2. **启动方式按项目类型判定**：有 `requirements.txt` → 按 PYTHON 项目，用 `venv/bin/python -m <模块名>` 启动；有 `package.json` → 按 Node 项目，用 `node <入口>` 启动。
3. **venv 只在「安装/重装」时创建**，单纯重启 MCP 不会重建 —— 所以插件目录里必须能自行产出 venv（或安装流程自动建）。

### 由此得出的设计结论

一个 MCP 插件要在市场里「装完即用」，必须满足：

- 依赖必须**声明在包里**（`package.json` / `requirements.txt`）；
- **重活（下载浏览器、预编译等）必须放到首次启动时由插件自己完成**（写进入口脚本，自举式）；
- 不能假设用户会去终端手动装包。

本项目自 v1.0.5 起按这个思路改造：`package.json` 声明 `@playwright/mcp`，`playwright_mcp.py` 作为**自举转发器**在首次启动时补齐 MCP 包与 Chromium。

---

## 两条发布路线

1. **直接上传当前本地包**：适合只发布当前构建产物的作者，不需 Git 仓库。Operit 会在当前 GitHub 账号的 `OperitForge` 仓库创建/更新 Release 并登记市场。
2. **引用 GitHub Release 资产**：适合长期维护仓库的作者。仓库持续保存源码、manifest、构建脚本与依赖清单；每次发布由作者构建资产、更新版本、整理提交与 tag、创建 Release，再到 Operit 中登记市场。

引用 Release 资产的操作顺序：

1. 在 Operit 应用中打开**发布页面**，选择本地已构建的插件文件（本仓库即 `config/mcp_config.json`）。
2. 「发布资源来源」选择 **引用 GitHub Release 资产**。
3. 填写作者仓库链接（如 `https://github.com/x15907982411/playwright-mcp-for-operit`），加载后选择 Release（如 `v1.0.5`）和对应 zip 资产。
4. 填写插件名称、介绍、分类、版本、支持的软件版本。
5. 将配置 JSON（见 `publish_config.example.json`，或直接使用仓库根 `config/mcp_config.json`）粘贴到配置区域。
6. 确认市场登记。Operit 会核对 Release 资产与本地文件一致，并由市场服务确认 Release 创建者即当前登录的 GitHub 作者。

> 注：Release 正文只保留自己的发布说明，无需添加 Operit 标记或校验文本。
> 发布页面会自动保存未提交的表单草稿，登记成功后清空。

---

## 配置 JSON 字段规范

### mcpServers.<server_id>

| 字段 | 必填 | 说明 |
|---|---|---|
| `command` | ✅ | 启动命令。**npx 类命令型插件填 `npx`**（系统自动转 `pnpm dlx`，依赖 `pnpm`）；**PYTHON 项目填 `~/mcp_plugins/<server_id>/venv/bin/python`** |
| `args` | 可选 | 启动参数数组。优先写相对路径（cwd 固定为 `~/mcp_plugins/<server_id>/`）；绝对路径必须是 **Linux 侧**路径，禁止写 `/sdcard/...` |
| `env` | 可选 | MCP 进程环境变量（token/Key 等），必须写在这里 |
| `autoApprove` | 可选 | 自动批准的敏感工具列表，默认 `[]` |
| `disabled` | 可选 | `true` 禁用该插件，默认 `false` |

### pluginMetadata.<server_id>

| 字段 | 必填 | 说明 |
|---|---|---|
| `type` | ✅ | `local`（本地 stdio）或 `remote`（远程 HTTP） |
| `connectionType` | ✅ | `stdio` / `streamableHttp` / `sse` |
| `installedPath` | ✅ | Android 侧插件源目录（用户导入/存放目录，非运行目录） |
| `name` | ✅ | 市场显示名称 |
| `version` | ✅ | 插件版本号 |
| `description` | ✅ | 市场卡片上的一句话能力描述 |
| `author` / `repoUrl` | 可选 | 作者名 / 源码仓库 URL |

> ⚠️ 本地插件实际写入 Operit 的 `mcp_config.json` 时，`pluginMetadata` **必须 15 字段全量**（`id`/`name`/`version`/`updatedAt`/`installedTime`/`isInstalled`/`logoUrl`/`longDescription`/`author`/`repoUrl`/`description`/`type`/`connectionType`/`installedPath`/`disabled`）。缺 `updatedAt` 等字段会导致 Operit 加载插件时空指针异常（MCPRepository NPE），表现为「永远加载不上」。

### 远程插件（type=remote）

不使用 `command/args`，改为：

```json
{
  "mcpServers": {
    "<server_id>": { "command": "", "args": [], "env": {}, "disabled": false }
  },
  "pluginMetadata": {
    "<server_id>": {
      "type": "remote",
      "connectionType": "streamableHttp",
      "endpoint": "https://example.com/mcp",
      "bearerToken": "",
      "headers": {},
      "name": "<显示名称>",
      "version": "1.0.0",
      "description": "<能力描述>"
    }
  }
}
```

---

## 本插件（Playwright MCP）的推荐配置

```json
{
  "mcpServers": {
    "playwright_mcp": {
      "command": "~/mcp_plugins/playwright_mcp/venv/bin/python",
      "args": ["-m", "playwright_mcp"],
      "autoApprove": [],
      "disabled": false,
      "env": {}
    }
  },
  "pluginMetadata": {
    "playwright_mcp": {
      "author": "x15907982411",
      "connectionType": "stdio",
      "description": "Playwright MCP - 网页自动化（导航/点击/填表/截图/snapshot）",
      "disabled": false,
      "id": "playwright_mcp",
      "installedPath": "/storage/emulated/0/Download/Operit/mcp_plugins/playwright_mcp",
      "installedTime": 1788600000000,
      "isInstalled": true,
      "logoUrl": "",
      "longDescription": "基于官方 @playwright/mcp 的网页自动化插件：headless Chromium 渲染，导航/快照/点击/填表/截图/网络抓包/控制台日志，共 24 个 browser_* 工具。",
      "name": "Playwright MCP for Operit",
      "repoUrl": "https://github.com/x15907982411/playwright-mcp-for-operit",
      "type": "local",
      "updatedAt": "2026-09-12T00:00:00Z",
      "version": "1.0.5"
    }
  }
}
```

**为什么这样填（v1.0.5 设计要点）：**

| 字段/文件 | 值 | 原因 |
|---|---|---|
| `command` | `venv/bin/python` | 有 `requirements.txt` → Operit 按 PYTHON 项目启动 |
| `args` | `["-m", "playwright_mcp"]` | 新版 Operit 强制「目录名 = 模块名」 |
| 包内 `playwright_mcp.py` | 必备 | venv 里没有这个模块就跑不起来；它同时承担自举职责 |
| 包内 `requirements.txt` | 必备（可只写注释） | 让 Operit 判定为 PYTHON 项目 |
| 包内 `package.json` | 必备 | 声明 `@playwright/mcp`，让 Operit 自动 npm install |
| Chromium | **不放进包**（150MB） | 由转发器首次启动时复用/下载 |
| `venv` | 不放进包 | 由安装流程或 `install.sh` 创建（重启不会重建） |

**首次启动行为（用户看到什么）：**

1. 市场装完 → 重启 MCP → 首次启动会依次检查：本地 MCP 包 → 全局 MCP 包 → 自动 `npm install`；然后检查 Chromium → 复用 → 自动下载（约 150MB，数分钟）。
2. 日志写到 `~/mcp_plugins/playwright_mcp/bootstrap.log`，可在 Operit 日志或文件管理器查看。
3. 若首次启动因下载超时失败，**再重启一次 MCP 即可**（包/浏览器已下载完成）。
4. 重启工具报 `Unknown error` 不代表失败 —— 以 `ping_mcp` 能否列出 24 个工具为准。

---

## 发布前自检清单

| 项 | 检查 |
|---|---|
| **zip 根结构** | 解压后直接是 `playwright_mcp/`（内含 `playwright_mcp.py`、`requirements.txt`、`package.json`、`mcp.config.json`） |
| **必需文件** | 上述 4 个文件齐全（缺 `playwright_mcp.py` 会导致 `ModuleNotFoundError`） |
| **配置 JSON** | `mcp.config.json` / 粘贴的配置 JSON 可被 `JSON.parse` 解析（无注释、无尾逗号） |
| **版本一致性** | `package.json` / `pluginMetadata.version` / README 徽章 / install.sh 头部四处一致 |
| **市场登记版本** | 必须**大于当前已有版本**（曾遇到 409 `version_conflict`：服务端拿应用版本参与比较，建议用 `1.0.x` 递增） |
| **Release 资产** | 若走引用路线，Release 资产必须与本地所选文件一致，且 Release 创建者 = 当前登录的 GitHub 作者 |
| **自测** | 在干净目录里仅放包内文件，直接 `python3 playwright_mcp.py` 看能否自举到启动（不依赖全局包） |

---

## 常见坑

- `serverId` 只允许 `a-zA-Z_` 和空格，不要随意改名（改名会导致旧配置残留）。
- 本地插件安装后，系统把 Android 侧目录复制到 Linux 侧 `~/mcp_plugins/<server_id>/` 再启动；`installedPath` 指向 Android 侧即可。
- 环境变量不要用 `read_environment_variable` / `write_environment_variable` 配置 MCP 的 key，必须写在 `mcpServers.<id>.env`。
- **依赖要写在 `package.json` / `requirements.txt` 里** —— 安装过程不会读 README。
- Chromium、大模型权重这类百 MB 级资源**不要塞进 zip**，交给插件自举；否则市场下载体验会很差。
- `--ignore-scripts` 会让 `postinstall` 失效，别把关键步骤放在那里。
- **`npm install` 必须在 Linux 文件系统内跑**：`/sdcard` 是 FUSE，不支持文件锁/符号链接，在 Android 侧目录装依赖会失败或产生半成品。
