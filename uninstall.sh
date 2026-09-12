#!/usr/bin/env bash
# ============================================================
# Playwright MCP for Operit - 卸载脚本 (v1.0.5)
#
# 用法:
#   bash uninstall.sh              # 移除插件（双路径目录 + mcp_config.json 条目，自动备份）
#   bash uninstall.sh --keep-files # 只移除配置条目，保留插件目录
#   bash uninstall.sh --dry-run    # 只打印将要做什么
#   bash uninstall.sh --purge      # 连 node_modules / Android 源目录一起删（chromium 不动）
#
# 环境变量: OPERIT_DATA_DIR（默认 /sdcard/Download/Operit）、LINUX_RUN_DIR（默认 $HOME/mcp_plugins）
# ============================================================
set -eu

MCP_ID="playwright_mcp"
OPERIT_DATA_DIR="${OPERIT_DATA_DIR:-/sdcard/Download/Operit}"
LINUX_RUN_DIR="${LINUX_RUN_DIR:-$HOME/mcp_plugins}"
ANDROID_DIR="$OPERIT_DATA_DIR/mcp_plugins/$MCP_ID"
MAIN_CFG="$OPERIT_DATA_DIR/mcp_plugins/mcp_config.json"
KEEP_FILES=0
DRY_RUN=0
PURGE=0

for arg in "$@"; do
  case "$arg" in
    --keep-files) KEEP_FILES=1 ;;
    --dry-run)    DRY_RUN=1    ;;
    --purge)      PURGE=1      ;;
    -h|--help)    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "⚠️  未知参数: $arg" ;;
  esac
done

run() {
  if [ "$DRY_RUN" = 1 ]; then echo "    [dry-run] $*"; else eval "$@"; fi
}

log() { echo "$*"; }

log "==> 卸载 Playwright MCP for Operit"

# 1. 从主配置移除两个条目
if [ -f "$MAIN_CFG" ]; then
  if command -v node >/dev/null 2>&1; then
    if [ "$DRY_RUN" = 0 ]; then
      cp "$MAIN_CFG" "$MAIN_CFG.bak.$(date +%s)" && log "    主配置已备份"
    fi
    if [ "$DRY_RUN" = 1 ]; then
      log "    [dry-run] 从 mcp_config.json 移除 mcpServers.playwright_mcp 与 pluginMetadata.playwright_mcp"
    else
      node - "$MAIN_CFG" <<'NODE'
const fs = require('fs');
const p = process.argv[2];
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) {
  console.error('❌ 主配置解析失败，跳过配置移除（请手动编辑）');
  process.exit(0);
}
const id = 'playwright_mcp';
let removed = 0;
if (cfg.mcpServers && cfg.mcpServers[id]) { delete cfg.mcpServers[id]; removed++; }
if (cfg.pluginMetadata && cfg.pluginMetadata[id]) { delete cfg.pluginMetadata[id]; removed++; }
fs.writeFileSync(p, JSON.stringify(cfg, null, 2));
console.log('    ✅ 已从主配置移除 ' + removed + ' 个条目');
NODE
    fi
  else
    log "    ⚠️ 未找到 node，请手动从 mcp_config.json 删除 playwright_mcp 条目"
  fi
else
  log "    主配置不存在，跳过（$MAIN_CFG）"
fi

# 2. 删目录
if [ "$KEEP_FILES" = 1 ]; then
  log "    --keep-files：保留插件目录"
else
  run "rm -rf '$LINUX_RUN_DIR/$MCP_ID'"
  if [ "$PURGE" = 1 ]; then
    run "rm -rf '$ANDROID_DIR'"
    log "    --purge：Android 源目录（含 node_modules）已删"
  else
    run "rm -f '$ANDROID_DIR/playwright_mcp.py' '$ANDROID_DIR/mcp.config.json' '$ANDROID_DIR/bootstrap.log'"
    log "    （Android 源目录其余文件保留；如需彻底删除加 --purge）"
  fi
  log "    ✅ 已移除：$LINUX_RUN_DIR/$MCP_ID"
fi

log ""
log "==> 收尾：在 Operit 内执行 restart_mcp_with_logs 使生效"
log "✅ 卸载完成"
