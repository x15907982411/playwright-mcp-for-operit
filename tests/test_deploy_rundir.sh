#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# deploy_run_dir() 的失败路径回归测试（install.sh）。
#
# 设计原则：只使用**确定性故障**，不依赖 chmod 000 之类的权限模拟
# （root 下 chmod 000 并不能阻止读写，会造成「测试声称失败、实际 cp 成功」的假绿）。
#
# 运行： bash tests/test_deploy_rundir.sh

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
INSTALLER="$REPO_ROOT/install.sh"
[ -f "$INSTALLER" ] || { echo "找不到 install.sh"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 提取函数定义（从 deploy_run_dir() 到其收尾的单独一行 "}"）
sed -n '/^deploy_run_dir() {$/,/^}$/p' "$INSTALLER" > "$WORK/fn.sh"
[ -s "$WORK/fn.sh" ] || { echo "未能从 install.sh 提取 deploy_run_dir"; exit 1; }

LINUX_RUN_DIR="$WORK/runhome"
mkdir -p "$LINUX_RUN_DIR"
# shellcheck disable=SC1091
source "$WORK/fn.sh"

PASS=0
FAILN=0
check() {
  if [ "$2" = "$3" ]; then
    echo "  ✓ $1"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $1（期望 $3，实际 $2）"
    FAILN=$((FAILN + 1))
  fi
}

DST="$LINUX_RUN_DIR/playwrightmcp"

# ---- 用例 1：源目录不存在 → 旧安装必须完好 ----
mkdir -p "$DST"
echo SENTINEL > "$DST/sentinel.txt"
( deploy_run_dir "$WORK/no_such_src" "$DST" ) >/dev/null 2>&1
check "用例1 退出码非 0" "$?" "1"
check "用例1 旧目录仍在" "$([ -f "$DST/sentinel.txt" ] && echo yes || echo no)" "yes"
check "用例1 未残留 staging" "$(ls -d "$LINUX_RUN_DIR"/playwrightmcp.staging.* 2>/dev/null | wc -l)" "0"

# ---- 用例 2：源目录缺少关键文件 → 部署校验必须拦住 ----
mkdir -p "$WORK/badsrc"
echo x > "$WORK/badsrc/some_file.txt"
( deploy_run_dir "$WORK/badsrc" "$DST" ) >/dev/null 2>&1
check "用例2 退出码非 0" "$?" "1"
check "用例2 旧目录仍在" "$([ -f "$DST/sentinel.txt" ] && echo yes || echo no)" "yes"

# ---- 用例 3：正常目录 → 完成替换且不留备份 ----
mkdir -p "$WORK/goodsrc"
echo x > "$WORK/goodsrc/playwrightmcp.py"
echo '{}' > "$WORK/goodsrc/package.json"
( deploy_run_dir "$WORK/goodsrc" "$DST" ) >/dev/null 2>&1
check "用例3 退出码 0" "$?" "0"
check "用例3 新文件到位" "$([ -f "$DST/playwrightmcp.py" ] && echo yes || echo no)" "yes"
check "用例3 旧哨兵已消失" "$([ -f "$DST/sentinel.txt" ] && echo yes || echo no)" "no"
check "用例3 无残留备份" "$(ls -d "$LINUX_RUN_DIR"/playwrightmcp.bak.* 2>/dev/null | wc -l)" "0"

echo
echo "deploy_run_dir 测试: PASS=$PASS FAIL=$FAILN"
[ "$FAILN" = 0 ]
