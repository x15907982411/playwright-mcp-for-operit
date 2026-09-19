#!/bin/bash
# ============================================================
#  Playwright MCP for Operit —— 卸载脚本
#  配套安装脚本：install.sh
#
#  用法：
#    bash uninstall.sh                    # 卸载插件（保留 Android 源目录）
#    bash uninstall.sh --keep-files       # 同上（显式）
#    bash uninstall.sh --purge            # 连 Android 源目录一起删除
#    bash uninstall.sh --dry-run          # 只预览，不写入
#
#  环境变量：
#    OPERIT_DATA_DIR      默认 /sdcard/Download/Operit
#    LINUX_RUN_DIR        默认 $HOME/mcp_plugins
# ============================================================
set -eu

MCP_ID="playwright_mcp"
OPERIT_DATA_DIR="${OPERIT_DATA_DIR:-/sdcard/Download/Operit}"
LINUX_RUN_DIR="${LINUX_RUN_DIR:-$HOME/mcp_plugins}"
MAIN_CFG="$OPERIT_DATA_DIR/mcp_plugins/mcp_config.json"
ANDROID_DIR="$OPERIT_DATA_DIR/mcp_plugins/$MCP_ID"
RUN_DIR="$LINUX_RUN_DIR/$MCP_ID"

DRY_RUN=0
PURGE=0

log()  { printf '%s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }

for arg in "$@"; do
  case "$arg" in
    --purge)      PURGE=1 ;;
    --keep-files) PURGE=0 ;;
    --dry-run)    DRY_RUN=1 ;;
    -h|--help)    sed -n '3,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) warn "未知参数: $arg（已忽略）" ;;
  esac
done

step "[1/4] 检查安装位置"
log "    Android 源目录 : $ANDROID_DIR"
log "    Linux 运行目录 : $RUN_DIR"
log "    主配置         : $MAIN_CFG"
log "    模式           : $( [ "$DRY_RUN" = 1 ] && echo 'DRY RUN' || echo '实际执行' )$( [ "$PURGE" = 1 ] && echo ' + PURGE' || echo '' )"

step "[2/4] 从 mcp_config.json 移除配置项"
if [ -f "$MAIN_CFG" ]; then
    if [ "$DRY_RUN" = 0 ]; then
      BAK="$MAIN_CFG.bak.$(date +%s)"
      if cp "$MAIN_CFG" "$BAK"; then
        log "    主配置已备份: $(basename "$BAK")"
      else
        log "    ⚠️  备份失败，已中止（原文件未改动）"; exit 1
      fi
      # 与 install.sh 一致：只保留最近 5 份备份
      # 注意：用 ls -1t 而非 find -printf（后者是 GNU 扩展，Termux 的 toybox find 不支持）
      ( cd "$(dirname "$MAIN_CFG")" && ls -1t "$(basename "$MAIN_CFG").bak."* 2>/dev/null | tail -n +6 | while IFS= read -r old; do rm -f -- "$old"; done ) || true
    fi
    if [ "$DRY_RUN" = 1 ]; then
      log "    [dry-run] 从 mcp_config.json 移除 mcpServers.playwright_mcp 与 pluginMetadata.playwright_mcp"
    else
      node - "$MAIN_CFG" <<'NODE'
const fs = require('fs');
const p = process.argv[2];
let d;
try { d = JSON.parse(fs.readFileSync(p, 'utf8')); }
catch (e) { console.error('    ⚠️  主配置解析失败，已跳过（原文件未改动）: ' + e.message); process.exit(1); }
let n = 0;
if (d.mcpServers && Object.prototype.hasOwnProperty.call(d.mcpServers, 'playwright_mcp')) {
  delete d.mcpServers.playwright_mcp; n++;
}
if (d.pluginMetadata && Object.prototype.hasOwnProperty.call(d.pluginMetadata, 'playwright_mcp')) {
  delete d.pluginMetadata.playwright_mcp; n++;
}
fs.writeFileSync(p, JSON.stringify(d, null, 2) + '\n');
console.log('    ✅ 已移除 ' + n + ' 个配置项');
NODE
    fi
else
    log "    ℹ️  主配置不存在，跳过"
fi

step "[3/4] 删除 Linux 运行目录"
if [ -d "$RUN_DIR" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      log "    [dry-run] 将删除 $RUN_DIR"
    else
      rm -rf "${LINUX_RUN_DIR:?}/$MCP_ID"
      log "    ✅ 已移除：$RUN_DIR"
    fi
else
    log "    ℹ️  运行目录不存在，跳过"
fi

step "[4/4] 处理 Android 源目录"
if [ "$PURGE" = 1 ]; then
    if [ -d "$ANDROID_DIR" ]; then
      if [ "$DRY_RUN" = 1 ]; then
        log "    [dry-run] 将删除 $ANDROID_DIR"
      else
        rm -rf "${OPERIT_DATA_DIR:?}/mcp_plugins/$MCP_ID"
        log "    ✅ 已移除：$ANDROID_DIR"
      fi
    else
      log "    ℹ️  源目录不存在，跳过"
    fi
else
    log "    ℹ️  保留源目录（如需彻底删除加 --purge）：$ANDROID_DIR"
fi

printf '\n'
log "==> 收尾：在 Operit 内执行 restart_mcp_with_logs 使生效"
log "✅ 卸载完成"
