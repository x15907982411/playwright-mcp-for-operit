#!/usr/bin/env bash
# ============================================================
# Playwright MCP for Operit - 一键部署脚本 (v1.0.2)
# 用法: bash install.sh
# 适用环境: Android + Termux/proot(Ubuntu) + node>=18 + Operit
#   非 Operit 用户请勿使用（配置合并路径与 Operit 深度耦合）
# 安全提示: 建议先 wget/curl 保存到本地审查一遍再执行
# 功能: 检查 node/npm → 安装 @playwright/mcp@0.0.79（锁版本）
#       → 定位/下载 chromium(arm64 headless) → 生成完整配置
#       （含 pluginMetadata 全字段，修复 Operit MCPRepository NPE）
#       → 自动合并进 Operit 主配置（原文件自动备份）+ 双路径部署
# 可覆盖变量: OPERIT_DATA_DIR（默认 /sdcard/Download/Operit）
#            PLAYWRIGHT_DOWNLOAD_HOST（默认 npmmirror 镜像）
# ============================================================
set -e
trap 'rm -f /tmp/playwright_mcp.segment.json' EXIT

MCP_ID="playwright_mcp"
MCP_VER="0.0.79"
OPERIT_DATA_DIR="${OPERIT_DATA_DIR:-/sdcard/Download/Operit}"
NPM_ROOT="$(npm root -g 2>/dev/null || echo /usr/lib/node_modules)"
CLI_JS="${NPM_ROOT}/@playwright/mcp/cli.js"
MAIN_CFG="${OPERIT_DATA_DIR}/mcp_plugins/mcp_config.json"
ANDROID_DIR="${OPERIT_DATA_DIR}/mcp_plugins/${MCP_ID}"
SEG="/tmp/playwright_mcp.segment.json"

echo "==> [1/5] 检查 node / npm"
command -v node >/dev/null 2>&1 || { echo "❌ node 未安装（需 ≥18）"; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "❌ npm 未安装";  exit 1; }
NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
if [ "$NODE_MAJOR" -lt 18 ]; then echo "❌ node 版本过低: $(node -v)（需 ≥18）"; exit 1; fi
echo "    node: $(node -v)  npm: $(npm -v)  npmRoot: $NPM_ROOT"

echo "==> [2/5] 安装 @playwright/mcp@${MCP_VER}（全局，锁版本）"
if [ ! -f "$CLI_JS" ]; then
  if ! npm i -g "@playwright/mcp@${MCP_VER}" > /tmp/pw_npm.log 2>&1; then
    echo "❌ npm 安装失败"
    echo "   国内加速: npm config set registry https://registry.npmmirror.com"
    tail -5 /tmp/pw_npm.log
    exit 1
  fi
else
  echo "    已存在，校验版本..."
fi
INSTALLED_VER=$(node -e "console.log(require('${CLI_JS}'.replace('cli.js','package.json')).version)" 2>/dev/null || echo "unknown")
if [ "$INSTALLED_VER" != "$MCP_VER" ]; then
  echo "❌ 版本不一致: 期望 ${MCP_VER}，实际 ${INSTALLED_VER}，请手动 npm i -g @playwright/mcp@${MCP_VER}"
  exit 1
fi
echo "    版本: ${INSTALLED_VER} ✅"

echo "==> [3/5] 定位 chromium（优先复用已安装，否则自动下载）"
find_chrome() {
  find ~/.cache/ms-playwright -maxdepth 4 -type f -name chrome -path '*chrome-linux*' 2>/dev/null | head -1
}
CHROME_BIN=""
[ -d ~/.cache/ms-playwright ] && CHROME_BIN=$(find_chrome)
if [ -z "$CHROME_BIN" ]; then
  echo "    未发现已装 chromium，尝试下载 arm64 版（约 150MB）..."
  cd "$NPM_ROOT/@playwright/mcp"
  if ! PLAYWRIGHT_DOWNLOAD_HOST="${PLAYWRIGHT_DOWNLOAD_HOST:-https://cdn.npmmirror.com/binaries/playwright}" \
       node node_modules/playwright/cli.js install chromium > /tmp/pw_dl.log 2>&1; then
    echo "❌ 自动下载失败（常见：镜像源未同步该版本 arm64 build，见 docs/TROUBLESHOOTING.md 问题 2）"
    echo "   可尝试: export PLAYWRIGHT_DOWNLOAD_HOST=<其他镜像> 后重跑本脚本"
    tail -5 /tmp/pw_dl.log
    echo "   请改用「复用已有 chromium」方案："
    echo "   ① find ~/.cache/ms-playwright -maxdepth 4 -type f -name chrome -path '*chrome-linux*'"
    echo "   ② 将输出路径填入配置 args 的 --executable-path 后，手动合并 config/mcp_config.json"
    exit 1
  fi
  CHROME_BIN=$(find_chrome)
fi
[ -z "$CHROME_BIN" ] && { echo "❌ chromium 定位失败"; exit 1; }
echo "    ✅ $CHROME_BIN"

echo "==> [4/5] 生成完整配置（pluginMetadata 全字段，修复 NPE）"
node - "$CHROME_BIN" "$MCP_VER" "$NPM_ROOT" > /dev/null <<'NODE'
const fs = require('fs');
const chrome = process.argv[2];
const ver = process.argv[3];
const npmRoot = process.argv[4];
const seg = {
  mcpServers: {
    playwright_mcp: {
      command: 'node',
      args: [npmRoot + '/@playwright/mcp/cli.js', '--headless', '--no-sandbox', '--executable-path', chrome],
      autoApprove: [],
      disabled: false,
      env: {}
    }
  },
  pluginMetadata: {
    playwright_mcp: {
      author: 'Microsoft',
      connectionType: 'stdio',
      description: 'Playwright MCP - 网页自动化（导航/点击/填表/截图/snapshot）',
      disabled: false,
      id: 'playwright_mcp',
      installedPath: '/storage/emulated/0/Download/Operit/mcp_plugins/playwright_mcp',
      installedTime: Date.now(),
      isInstalled: true,
      logoUrl: '',
      longDescription: 'Playwright MCP - 网页自动化（导航/点击/填表/截图/snapshot）',
      name: 'Playwright MCP for Operit',
      repoUrl: 'https://github.com/microsoft/playwright-mcp',
      type: 'local',
      updatedAt: new Date().toISOString(),
      version: ver
    }
  }
};
fs.writeFileSync('/tmp/playwright_mcp.segment.json', JSON.stringify(seg, null, 2));
NODE
echo "    ✅ 配置片段已生成: $SEG"

echo "==> [5/5] 部署：合并主配置（自动备份）+ 双路径目录"
mkdir -p "$ANDROID_DIR"
if [ -f "$MAIN_CFG" ]; then
  cp "$MAIN_CFG" "$MAIN_CFG.bak.$(date +%s)" && echo "    主配置已备份: $MAIN_CFG.bak.*"
fi
node - "$MAIN_CFG" <<'NODE'
const fs = require('fs');
const mainPath = process.argv[2];
const segPath = '/tmp/playwright_mcp.segment.json';
let seg;
try {
  seg = JSON.parse(fs.readFileSync(segPath, 'utf8'));
} catch (e) {
  console.error('❌ 配置片段损坏，请重跑本脚本'); process.exit(1);
}
let main = {};
if (fs.existsSync(mainPath)) {
  try {
    main = JSON.parse(fs.readFileSync(mainPath, 'utf8'));
  } catch (e) {
    console.error('❌ 主配置 JSON 解析失败（可能被手动改坏）: ' + mainPath);
    console.error('   请检查该文件格式，或从备份 .bak.* 恢复后重跑');
    process.exit(1);
  }
}
main.mcpServers = main.mcpServers || {};
main.pluginMetadata = main.pluginMetadata || {};
main.mcpServers.playwright_mcp = seg.mcpServers.playwright_mcp;
main.pluginMetadata.playwright_mcp = seg.pluginMetadata.playwright_mcp;
fs.writeFileSync(mainPath, JSON.stringify(main, null, 2));
console.log('    ✅ 已合并进 ' + mainPath);
NODE
node -e "const s=JSON.parse(require('fs').readFileSync('/tmp/playwright_mcp.segment.json','utf8'));require('fs').writeFileSync('${ANDROID_DIR}/mcp.config.json', JSON.stringify({mcpServers:s.mcpServers},null,2))"
mkdir -p /root/mcp_plugins
cp -r "$ANDROID_DIR" /root/mcp_plugins/
echo "    ✅ 双路径部署完成（Android 源 + Linux 运行目录）"

echo ""
echo "==> 收尾（Operit 内操作）："
echo "  1. 重启 MCP: operit_editor:restart_mcp_with_logs → 预期全部 success"
echo "  2. 验证:     ping_mcp(playwright_mcp) → 应列出 24 个 browser_* 工具"
echo "  3. 冒烟:     browser_navigate('https://www.baidu.com')"
echo "✅ 部署完成"