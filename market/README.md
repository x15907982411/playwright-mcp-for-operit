# 发布到 Operit 市场

本目录包含发布到 Operit 插件市场所需的配置模板与说明。

## 发布流程（引用 GitHub Release 资产路线）

1. 在 Operit 应用中打开**发布页面**，选择本地已构建的插件文件（本仓库即 `config/mcp_config.json`）。
2. 「发布资源来源」选择 **引用 GitHub Release 资产**。
3. 填写作者仓库链接（如 `https://github.com/x15907982411/playwright-mcp-for-operit`），加载后选择 Release（如 `v1.0.0`）和对应 zip 资产。
4. 填写插件名称、介绍、分类、版本、支持的软件版本。
5. 将配置 JSON（见 `publish_config.example.json`，或直接使用仓库根 `config/mcp_config.json`）粘贴到配置区域。
6. 确认市场登记。Operit 会核对 Release 资产与本地文件一致，并由市场服务确认 Release 创建者即当前登录的 GitHub 作者。

> 注：Release 正文只保留自己的发布说明，无需添加 Operit 标记或校验文本。

## 配置 JSON 字段规范

### mcpServers.<server_id>

| 字段 | 必填 | 说明 |
|---|---|---|
| `command` | ✅ | 启动命令：`node` / `python` / `uvx` 等。`npx` 类命令型插件填 `npx`，系统会自动转为 `pnpm dlx` 执行（实际依赖 `pnpm`，需在 Linux 终端装好） |
| `args` | 可选 | 启动参数数组。**优先写相对路径**（cwd 固定为 `~/mcp_plugins/<server_id>/`）；绝对路径必须是 **Linux 侧**路径，禁止写 `/sdcard/...` Android 路径 |
| `env` | 可选 | MCP 进程环境变量（token/Key 等），必须写在这里 |
| `autoApprove` | 可选 | 自动批准的敏感工具列表，默认 `[]` |
| `disabled` | 可选 | `true` 禁用该插件，默认 `false` |

### pluginMetadata.<server_id>

| 字段 | 必填 | 说明 |
|---|---|---|
| `type` | ✅ | `local`（本地 stdio 插件）或 `remote`（远程 HTTP 插件） |
| `connectionType` | ✅ | `stdio`（本地）或 `streamableHttp` / `sse`（远程） |
| `installedPath` | ✅ | Android 侧插件源目录（用户导入/存放目录，非运行目录） |
| `name` | ✅ | 市场显示名称 |
| `version` | ✅ | 插件版本号 |
| `description` | ✅ | 市场卡片上的一句话能力描述 |
| `author` | 可选 | 作者名 |
| `repoUrl` | 可选 | 源码仓库 URL |

### 远程插件（type=remote）

不使用 `command/args`，改为：

```json
{
  "mcpServers": {
    "<server_id>": {
      "command": "",
      "args": [],
      "env": {},
      "disabled": false
    }
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

## 常见坑

- serverId 只允许 `a-zA-Z_` 和空格，不要随意改名（改名会导致旧配置残留）。
- 本地插件安装后，系统把 Android 侧目录复制到 Linux 侧 `~/mcp_plugins/<server_id>/` 再启动；`installedPath` 指向 Android 侧即可。
- 环境变量不要用 `read_environment_variable` / `write_environment_variable` 配置 MCP 的 key，必须写在 `mcpServers.<id>.env`。
- 安装是否成功以「工具可调用/服务可响应」为准，不要只看 `server_status.json`。