#!/usr/bin/env bash
# ============================================================
# Playwright MCP for Operit - 一键部署脚本
# 用法: bash install.sh
# 功能: 检查 node/npm → 安装 @playwright/mcp → 定位/下载
#       chromium(arm64 headless) → 生成 mcp_config.json 片段
# ============================================================
set -e

MCP_ID="playwright_mcp"
CLI_JS="/usr/lib/node_modules/@playwright/mcp/cli.js"

echo "==> [1/4] 检查 node / npm"
command -v node >/dev/null 2>&1 || { echo "❌ node 未安装"; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "❌ npm 未安装";  exit 1; }
echo "    node: $(node -v)  npm: $(npm -v)"

echo "==> [2/4] 安装 @playwright/mcp（全局）"
if [ ! -f "$CLI_JS" ]; then
  npm i -g @playwright/mcp || { echo "❌ npm 安装失败（可尝试: npm config set registry https://registry.npmmirror.com）"; exit 1; }
fi
echo "    ✅ $(node -e "console.log(require('$CLI_JS'.replace('cli.js','package.json')).version)")"

echo "==> [3/4] 定位 chromium（优先复用已安装，否则自动下载）"
CHROME_BIN=""
if [ -d ~/.cache/ms-playwright ]; then
  CHROME_BIN=$(find ~/.cache/ms-playwright -maxdepth 4 -type f -name chrome -path '*chrome-linux*' 2>/dev/null | head -1)
fi
if [ -z "$CHROME_BIN" ]; then
  echo "    未发现已装 chromium，正在下载 arm64 headless 版（首次约 150MB）..."
  cd /usr/lib/node_modules/@playwright/mcp
  node node_modules/playwright/cli.js install chromium
  CHROME_BIN=$(find ~/.cache/ms-playwright -maxdepth 4 -type f -name chrome -path '*chrome-linux*' 2>/dev/null | head -1)
fi
[ -z "$CHROME_BIN" ] && { echo "❌ chromium 定位失败"; exit 1; }
echo "    ✅ $CHROME_BIN"

echo "==> [4/4] 生成配置片段（打印到屏幕，粘贴进 mcp_config.json）"
cat <<EOF
{
  "mcpServers": {
    "$MCP_ID": {
      "command": "node",
      "args": [
        "$CLI_JS",
        "--headless",
        "--no-sandbox",
        "--executable-path",
        "$CHROME_BIN"
      ],
      "disabled": false,
      "env": {}
    }
  },
  "pluginMetadata": {
    "$MCP_ID": {
      "type": "local",
      "connectionType": "stdio",
      "installedPath": "/sdcard/Download/Operit/mcp_plugins/$MCP_ID"
    }
  }
}
EOF

echo ""
echo "==> 后续步骤（双路径部署）:"
echo "  mkdir -p /sdcard/Download/Operit/mcp_plugins/$MCP_ID"
echo "  将上面 JSON 合并进 /sdcard/Download/Operit/mcp_plugins/mcp_config.json"
echo "  cp -r /sdcard/Download/Operit/mcp_plugins/$MCP_ID /root/mcp_plugins/"
echo "  Operit 内触发 restart_mcp_with_logs → ping_mcp($MCP_ID) 验证"
echo "✅ 完成"
