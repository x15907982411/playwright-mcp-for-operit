#!/usr/bin/env bash
# ============================================================
# Playwright MCP for Operit - 一键部署脚本 (v1.0.5)
#
# 用法:
#   bash install.sh                 # 默认：依赖装到 Linux 运行目录（推荐）
#   bash install.sh --global        # 依赖装到全局 node_modules
#   bash install.sh --skip-deps     # 跳过依赖安装（交给自举转发器首次启动时处理）
#   bash install.sh --dry-run       # 只检查与打印，不写任何文件
#
# 适用环境: Android + proot(Ubuntu) / Termux + node>=18 + Operit
#   非 Operit 用户请勿使用（配置合并路径与 Operit 深度耦合）
#   推荐在 proot 环境执行（Termux 与 proot 的 ~/.cache 不互通，双环境会重复下载）
#
# 安全提示: 建议先 curl/wget 保存到本地审查一遍再执行（非 curl|bash 管道）
#
# 功能:
#   1. 环境检查（node/npm + 版本）
#   2. 部署插件文件（转发器 / requirements.txt / package.json / mcp.config.json）
#   3. Chromium 探测（复用优先；缺失时不阻塞，交给转发器自举）
#   4. 生成完整 pluginMetadata 配置（15 字段，防 Operit MCPRepository NPE）+ 合并主配置
#   5. 双路径部署（Android 源目录 + Linux 运行目录）+ 依赖安装 + venv 准备 + 结构校验
#
# 重要设计说明:
#   - npm install 必须在 Linux 文件系统内执行 —— /sdcard 是 FUSE，不支持文件锁与
#     符号链接，在 Android 侧目录跑 npm 会失败或产生半成品。因此 local 模式的安装
#     动作发生在双路径部署完成后，在 Linux 运行目录内执行。
#   - venv 不可缺：启动命令是 venv/bin/python -m playwright_mcp，而 Operit 只在
#     「安装/重装」时创建 venv，单纯重启不会重建，因此脚本自己先建好。
#
# 可覆盖变量:
#   OPERIT_DATA_DIR      默认 /sdcard/Download/Operit
#   LINUX_RUN_DIR        默认 $HOME/mcp_plugins
#   PW_MCP_INSTALL_MODE  local|global|skip
#   PW_MCP_NPM_REGISTRY  自定义 npm registry（国内加速）
# ============================================================
# 注意：不用 `pipefail`——本脚本大量使用 `cmd | head -1` 取首行，
# head 提前关闭管道会产生 SIGPIPE，配合 pipefail 会让 set -e 误杀脚本。
set -eu

MCP_ID="playwright_mcp"
MCP_VER="0.0.80"
OPERIT_DATA_DIR="${OPERIT_DATA_DIR:-/sdcard/Download/Operit}"
LINUX_RUN_DIR="${LINUX_RUN_DIR:-$HOME/mcp_plugins}"
INSTALL_MODE="${PW_MCP_INSTALL_MODE:-local}"
DRY_RUN=0
REPO_SLUG="x15907982411/playwright-mcp-for-operit"

SEG_FILE=""
ANDROID_DIR=""
cleanup() { [ -n "$SEG_FILE" ] && rm -f "$SEG_FILE" 2>/dev/null || true; }
trap cleanup EXIT

usage() { sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
  case "$arg" in
    --global)     INSTALL_MODE="global" ;;
    --skip-deps)  INSTALL_MODE="skip"   ;;
    --dry-run)    DRY_RUN=1             ;;
    -h|--help)    usage; exit 0          ;;
    *) echo "⚠️  未知参数: $arg（可用: --global --skip-deps --dry-run --help）" ;;
  esac
done

log()  { echo "$*"; }
warn() { echo "⚠️  $*" >&2; }
step() { echo; echo "==> $*"; }

NPM_REG_ARGS=()
[ -n "${PW_MCP_NPM_REGISTRY:-}" ] && NPM_REG_ARGS=(--registry "$PW_MCP_NPM_REGISTRY")

# ---------------------------------------------------------------- 1. 环境检查
step "[1/6] 环境检查"
command -v node >/dev/null 2>&1 || { echo "❌ node 未安装（需 ≥ 18）"; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "❌ npm 未安装"; exit 1; }
NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]")"
if [ "$NODE_MAJOR" -lt 18 ]; then echo "❌ node 版本过低: $(node -v)（需 ≥18）"; exit 1; fi
log "    node      : $(command -v node) ($(node -v))"
log "    npm       : $(npm -v)"
log "    Android 源: $OPERIT_DATA_DIR/mcp_plugins/$MCP_ID"
log "    Linux 运行: $LINUX_RUN_DIR/$MCP_ID"
log "    依赖模式  : $INSTALL_MODE$( [ "$DRY_RUN" = 1 ] && echo '   [DRY RUN]' || true )"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORWARDER_TEMPLATE="$SCRIPT_DIR/scripts/playwright_mcp.py"

ANDROID_DIR="$OPERIT_DATA_DIR/mcp_plugins/$MCP_ID"
RUN_DIR="$LINUX_RUN_DIR/$MCP_ID"

# ---------------------------------------------------------------- 2. 插件文件准备
step "[2/6] 准备插件文件（转发器 / 依赖声明 / 标志文件）"
if [ "$DRY_RUN" = 1 ]; then
  log "    [dry-run] 将在 $ANDROID_DIR 放置 4 个文件"
else
  mkdir -p "$ANDROID_DIR"
  if [ ! -f "$FORWARDER_TEMPLATE" ]; then
    warn "未找到 $FORWARDER_TEMPLATE（脚本可能被单独下载）"
    warn "   请从仓库 scripts/playwright_mcp.py 获取转发器，或直接使用 Release zip"
    exit 1
  fi
  cp "$FORWARDER_TEMPLATE" "$ANDROID_DIR/playwright_mcp.py"
  cp "$SCRIPT_DIR/requirements.txt" "$ANDROID_DIR/requirements.txt" 2>/dev/null \
    || printf '# 无 Python 依赖；仅用于 PYTHON 项目判定\n' > "$ANDROID_DIR/requirements.txt"
  if [ -f "$SCRIPT_DIR/package.json" ]; then
    cp "$SCRIPT_DIR/package.json" "$ANDROID_DIR/package.json"
  else
    printf '{\n  "name": "playwright-mcp-for-operit-runtime",\n  "private": true,\n  "dependencies": { "%s": "%s" }\n}\n' "@playwright/mcp" "$MCP_VER" > "$ANDROID_DIR/package.json"
  fi
  log "    ✅ playwright_mcp.py / requirements.txt / package.json"
fi

# ---------------------------------------------------------------- 3. Chromium 探测
step "[3/6] Chromium 探测（复用优先，不阻塞）"
find_chrome() {
  local best="" best_build=0 base found build
  for base in "$HOME/.cache/ms-playwright" "/root/.cache/ms-playwright" "${PLAYWRIGHT_BROWSERS_PATH:-}"; do
    [ -n "$base" ] && [ -d "$base" ] || continue
    while IFS= read -r found; do
      [ -n "$found" ] || continue
      build="$(printf '%s' "$found" | sed -n 's|.*chromium-\([0-9][0-9]*\).*|\1|p' | head -1 || true)"
      [ -n "$build" ] || build=0
      if [ "$build" -gt "$best_build" ] 2>/dev/null; then
        best_build="$build"; best="$found"
      elif [ -z "$best" ]; then
        best="$found"
      fi
    done < <(find "$base" -maxdepth 4 -type f -name chrome -path '*chrome-linux*' -size +1M 2>/dev/null || true)
  done
  [ -n "$best" ] && printf '%s' "$best"
}
CHROME_BIN="$(find_chrome || true)"
if [ -n "$CHROME_BIN" ]; then
  CHROME_BUILD="$(printf '%s' "$CHROME_BIN" | sed -n 's|.*chromium-\([0-9][0-9]*\).*|\1|p' | head -1 || true)"
  log "    ✅ 复用已有 Chromium：$CHROME_BIN（build=${CHROME_BUILD:-未知}）"
  if [ -n "$CHROME_BUILD" ] && [ "$CHROME_BUILD" -lt 1243 ] 2>/dev/null; then
    warn "build=${CHROME_BUILD} 低于官方期望 1243；跨 build 复用实测兼容，若异常请删除后重跑"
  fi
  MISSING="$( (ldd "$CHROME_BIN" 2>/dev/null || true) | grep 'not found' 2>/dev/null | awk '{print $1}' | sort -u | head -5 | tr '\n' ' ' || true)"
  if [ -n "$MISSING" ]; then
    warn "检测到缺失共享库: $MISSING"
    warn "   建议安装: apt install -y libnss3 libatk-bridge2.0-0 libdrm2 libxkbcommon0 libasound2 libcups2 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2"
  fi
else
  log "    未发现本机 Chromium"
  log "    → 首次启动时由转发器自动下载（约 150MB；可用 PW_MCP_AUTO_DOWNLOAD=0 关闭）"
fi

# ---------------------------------------------------------------- 4. 生成配置
step "[4/6] 生成 pluginMetadata 完整配置（15 字段，防 NPE）"
SEG_FILE="$(mktemp /tmp/playwright_mcp.segment.XXXXXX.json)"
INSTALLED_PATH="$(printf '%s' "$ANDROID_DIR" | sed 's|^/sdcard/|/storage/emulated/0/|')"
node - "$SEG_FILE" "$MCP_VER" "$INSTALLED_PATH" "$REPO_SLUG" <<'NODE'
const fs = require('fs');
const [segPath, ver, installedPath, repoSlug] = process.argv.slice(2);
const seg = {
  mcpServers: {
    playwright_mcp: {
      command: '~/mcp_plugins/playwright_mcp/venv/bin/python',
      args: ['-m', 'playwright_mcp'],
      autoApprove: [],
      disabled: false,
      env: {},
    },
  },
  pluginMetadata: {
    playwright_mcp: {
      author: 'x15907982411',
      connectionType: 'stdio',
      description: 'Playwright MCP - 网页自动化（导航/点击/填表/截图/snapshot）',
      disabled: false,
      id: 'playwright_mcp',
      installedPath,
      installedTime: Date.now(),
      isInstalled: true,
      logoUrl: '',
      longDescription: '基于官方 @playwright/mcp 的网页自动化插件：headless Chromium 渲染，导航/快照/点击/填表/截图/网络抓包/控制台日志，共 24 个 browser_* 工具。',
      name: 'Playwright MCP for Operit',
      repoUrl: 'https://github.com/' + repoSlug,
      type: 'local',
      updatedAt: new Date().toISOString(),
      version: ver,
    },
  },
};
fs.writeFileSync(segPath, JSON.stringify(seg, null, 2));
NODE
log "    ✅ 配置片段已生成"

# ---------------------------------------------------------------- 5. 双路径部署
step "[5/6] 双路径部署（Android 源目录 + Linux 运行目录）"
MAIN_CFG="$OPERIT_DATA_DIR/mcp_plugins/mcp_config.json"
if [ "$DRY_RUN" = 1 ]; then
  log "    [dry-run] 跳过写文件"
else
  node -e "const fs=require('fs');const s=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));fs.writeFileSync(process.argv[2],JSON.stringify({mcpServers:s.mcpServers},null,2));" \
    "$SEG_FILE" "$ANDROID_DIR/mcp.config.json"

  if [ -f "$MAIN_CFG" ]; then
    BAK_FILE="$MAIN_CFG.bak.$(date +%s)"
    cp "$MAIN_CFG" "$BAK_FILE" && log "    主配置已备份: $(basename "$BAK_FILE")"
    ( cd "$(dirname "$MAIN_CFG")" && ls -1t "$(basename "$MAIN_CFG").bak."* 2>/dev/null | tail -n +6 | while IFS= read -r old; do rm -f -- "$old"; done ) || true
  fi
  node - "$MAIN_CFG" "$SEG_FILE" <<'NODE'
const fs = require('fs');
const [mainPath, segPath] = process.argv.slice(2);
const seg = JSON.parse(fs.readFileSync(segPath, 'utf8'));
let main = {};
if (fs.existsSync(mainPath)) {
  try {
    main = JSON.parse(fs.readFileSync(mainPath, 'utf8'));
  } catch (e) {
    console.error('❌ 主配置 JSON 解析失败（可能被手动改坏）: ' + mainPath);
    console.error('   请检查该文件，或从 .bak.* 备份恢复后重跑');
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

  mkdir -p "$LINUX_RUN_DIR"
  rm -rf "${LINUX_RUN_DIR:?}/$MCP_ID"
  cp -r "$ANDROID_DIR" "$LINUX_RUN_DIR/"
  rm -rf "$RUN_DIR/node_modules" 2>/dev/null || true
  log "    ✅ $ANDROID_DIR"
  log "    ✅ $RUN_DIR"
fi

# ---------------------------------------------------------------- 5.5 依赖安装
if [ "$INSTALL_MODE" != "skip" ] && [ "$DRY_RUN" = 0 ]; then
  step "[5.5/6] 安装依赖（@playwright/mcp@${MCP_VER}）"
  if [ "$INSTALL_MODE" = "global" ]; then
    log "    目标: 全局 node_modules"
    if npm i -g --no-audit --no-fund "${NPM_REG_ARGS[@]+${NPM_REG_ARGS[@]}}" "@playwright/mcp@${MCP_VER}" >/tmp/pw_npm.log 2>&1; then
      log "    ✅ 全局安装完成"
    else
      warn "全局安装失败（常见 EACCES/EPERM → proot 需 root；Termux 需 npm prefix 可写）"
      warn "   将由转发器首次启动时重试；国内加速: npm config set registry https://registry.npmmirror.com"
      tail -5 /tmp/pw_npm.log 2>/dev/null || true
    fi
  else
    log "    目标: $RUN_DIR/node_modules（Linux 文件系统，规避 /sdcard FUSE 限制）"
    if ( cd "$RUN_DIR" && npm install --no-audit --no-fund "${NPM_REG_ARGS[@]+${NPM_REG_ARGS[@]}}" >/tmp/pw_npm.log 2>&1 ); then
      log "    ✅ 依赖已安装（启动时无需再下载）"
    else
      warn "npm install 失败，将由转发器首次启动时重试"
      warn "   国内加速: npm config set registry https://registry.npmmirror.com"
      tail -5 /tmp/pw_npm.log 2>/dev/null || true
    fi
  fi
elif [ "$INSTALL_MODE" = "skip" ]; then
  step "[5.5/6] 跳过依赖安装（交给转发器首次启动时自举）"
fi

# ---------------------------------------------------------------- 5.6 venv（PYTHON 项目启动必需）
# 启动命令是 venv/bin/python -m playwright_mcp，而 Operit 只在「安装/重装」时
# 创建 venv（单纯重启不会重建），因此脚本自己先建好，避免首次重启报错。
if [ "$DRY_RUN" = 0 ]; then
  step "[5.6/6] 准备 venv（$RUN_DIR/venv）"
  if [ -x "$RUN_DIR/venv/bin/python" ]; then
    log "    ✅ 已存在，跳过"
  elif python3 -m venv "$RUN_DIR/venv" >/dev/null 2>&1; then
    log "    ✅ 已创建（启动命令 venv/bin/python -m playwright_mcp 可用）"
  else
    warn "venv 创建失败（缺 python3-venv？）—— Operit 安装/重装插件时会自动创建"
  fi
fi

# ---------------------------------------------------------------- 6. 结构校验
step "[6/6] 结构校验"
if [ "$DRY_RUN" = 1 ]; then
  log "    [dry-run] 跳过"
else
  OK=1
  for f in playwright_mcp.py requirements.txt package.json mcp.config.json; do
    [ -f "$ANDROID_DIR/$f" ] && log "    ✅ Android/$f" || { warn "缺少 Android/$f"; OK=0; }
  done
  for f in playwright_mcp.py requirements.txt package.json; do
    [ -f "$RUN_DIR/$f" ] && log "    ✅ Linux/$f" || { warn "缺少 Linux/$f"; OK=0; }
  done
  if [ -f "$RUN_DIR/node_modules/@playwright/mcp/cli.js" ]; then
    log "    ✅ MCP 包已就位（node_modules）"
  else
    log "    ℹ️  MCP 包未就位（将由转发器首次启动时安装）"
  fi
  if [ -x "$RUN_DIR/venv/bin/python" ]; then
    log "    ✅ venv 已就位"
  else
    log "    ℹ️  venv 未就位（Operit 安装/重装时会创建）"
  fi
  if node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$ANDROID_DIR/mcp.config.json" 2>/dev/null; then
    log "    ✅ mcp.config.json JSON 合法"
  else
    warn "mcp.config.json 非法"; OK=0
  fi
  [ "$OK" = 1 ] || warn "存在校验项失败，请查看上面输出"
fi

# ---------------------------------------------------------------- 收尾
echo
echo "==> 收尾（在 Operit 内操作）："
echo "  1. 重启 MCP: operit_editor:restart_mcp_with_logs → 预期全部 success"
echo "  2. 验证:     ping_mcp(playwright_mcp) → 应列出 24 个 browser_* 工具"
echo "  3. 冒烟:     browser_navigate('https://www.baidu.com')"
echo ""
echo "  ℹ️  首次启动若缺依赖/Chromium，会自动补齐（日志：$RUN_DIR/bootstrap.log）"
echo "  🗑  卸载：bash uninstall.sh"
echo "✅ 部署完成"
