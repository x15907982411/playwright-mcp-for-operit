#!/usr/bin/env bash
# commit_keepdeps_files() 的失败回滚测试。
#
# 测试手法：在 PATH 前置一个「第 2 次调用就失败」的假 mv，
# 这样能确定性地让提交阶段中途断掉，而不依赖权限/磁盘等外界因素。

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
INSTALLER="$REPO_ROOT/install.sh"
[ -f "$INSTALLER" ] || { echo "找不到 install.sh"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sed -n '/^commit_keepdeps_files() {$/,/^}$/p' "$INSTALLER" > "$WORK/fn.sh"
[ -s "$WORK/fn.sh" ] || { echo "未能提取 commit_keepdeps_files"; exit 1; }
# shellcheck disable=SC1091
source "$WORK/fn.sh"

# 函数体里用到了 install.sh 的 log()，这里补一个静默版
log() { :; }

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

mksrc() {
  mkdir -p "$1"
  echo "NEW-${2}-py"  > "$1/playwrightmcp.py"
  echo "NEW-${2}-req" > "$1/requirements.txt"
  echo "NEW-${2}-pkg" > "$1/package.json"
}
mkdst() {
  mkdir -p "$1"
  echo "OLD-py"  > "$1/playwrightmcp.py"
  echo "OLD-req" > "$1/requirements.txt"
  echo "OLD-pkg" > "$1/package.json"
}

# ---------- 用例1：正常提交 ----------
SRC1="$WORK/src1"; DST1="$WORK/dst1"
mksrc "$SRC1" good
mkdst "$DST1"
( commit_keepdeps_files "$SRC1" "$DST1" ) >/dev/null 2>&1
rc1=$?
check "用例1 退出码 0" "$rc1" "0"
check "用例1 py 已更新" "$(cat "$DST1/playwrightmcp.py")" "NEW-good-py"
check "用例1 req 已更新" "$(cat "$DST1/requirements.txt")" "NEW-good-req"
check "用例1 pkg 已更新" "$(cat "$DST1/package.json")" "NEW-good-pkg"
check "用例1 无 .tmp 残留" "$(ls "$DST1"/*.tmp.* 2>/dev/null | wc -l)" "0"
check "用例1 无 .old 残留" "$(ls "$DST1"/*.old.* 2>/dev/null | wc -l)" "0"

# ---------- 用例2：第二个 mv 失败 → 必须整体回滚 ----------
mkdir -p "$WORK/fakebin"
cat > "$WORK/fakebin/mv" <<'FAKEMV'
#!/usr/bin/env bash
CNT=/tmp/pw_fake_mv_count
n=$(cat "$CNT" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$CNT"
if [ "$n" = "2" ]; then
  echo "[fake mv] 模拟第二次调用失败" >&2
  exit 1
fi
exec /bin/mv "$@"
FAKEMV
chmod +x "$WORK/fakebin/mv"

SRC2="$WORK/src2"; DST2="$WORK/dst2"
mksrc "$SRC2" bad
mkdst "$DST2"
rm -f /tmp/pw_fake_mv_count
( PATH="$WORK/fakebin:$PATH" commit_keepdeps_files "$SRC2" "$DST2" ) >/dev/null 2>&1
rc=$?
check "用例2 退出码非 0" "$([ "$rc" != 0 ] && echo yes || echo no)" "yes"
check "用例2 py 已回滚为旧版" "$(cat "$DST2/playwrightmcp.py")" "OLD-py"
check "用例2 req 仍为旧版" "$(cat "$DST2/requirements.txt")" "OLD-req"
check "用例2 pkg 仍为旧版" "$(cat "$DST2/package.json")" "OLD-pkg"
check "用例2 无 .tmp 残留" "$(ls "$DST2"/*.tmp.* 2>/dev/null | wc -l)" "0"
check "用例2 无 .old 残留" "$(ls "$DST2"/*.old.* 2>/dev/null | wc -l)" "0"

# ---------- 用例3：第二个 mv 失败 + 回滚（第三次 mv）也失败 → 备份必须保留 ----------
# 这是「最后一道防线」：如果连恢复都失败，程序绝不能把唯一的 .old 备份删掉。
cat > "$WORK/fakebin/mv3" <<'FAKEMV3'
#!/usr/bin/env bash
CNT=/tmp/pw_fake_mv3_count
n=$(cat "$CNT" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$CNT"
if [ "$n" = "2" ] || [ "$n" = "3" ]; then
  echo "[fake mv3] 模拟第 $n 次失败" >&2
  exit 1
fi
exec /bin/mv "$@"
FAKEMV3
chmod +x "$WORK/fakebin/mv3"
mkdir -p "$WORK/fakebin3"
cp "$WORK/fakebin/mv3" "$WORK/fakebin3/mv"
chmod +x "$WORK/fakebin3/mv"

SRC3="$WORK/src3"; DST3="$WORK/dst3"
mksrc "$SRC3" worst
mkdst "$DST3"
rm -f /tmp/pw_fake_mv3_count
out3=$( PATH="$WORK/fakebin3:$PATH" commit_keepdeps_files "$SRC3" "$DST3" 2>&1 )
rc3=$?
check "用例3 退出码非 0" "$([ "$rc3" != 0 ] && echo yes || echo no)" "yes"
check "用例3 提示「回滚未完成」" "$(printf '%s' "$out3" | grep -c '回滚未完成')" "1"
check "用例3 有恢复失败的明确提示" "$(printf '%s' "$out3" | grep -c '恢复失败')" "1"
check "用例3 .old 备份全保留（3 个）" "$(ls "$DST3"/*.old.* 2>/dev/null | wc -l)" "3"
check "用例3 .tmp 已清理" "$(ls "$DST3"/*.tmp.* 2>/dev/null | wc -l)" "0"

# ---------- 用例4：升级前某个文件不存在 → 回滚时必须删掉新建的它 ----------
# 场景：py/py 旧版存在，requirements.txt 升级前不存在，第三个（package.json）替换失败。
# 期望：py 恢复旧版、requirements.txt 被删除、package.json 保持旧版、无 .old 残留。
cat > "$WORK/fakebin/mv4" <<'FAKEMV4'
#!/usr/bin/env bash
CNT=/tmp/pw_fake_mv4_count
n=$(cat "$CNT" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$CNT"
if [ "$n" = "3" ]; then
  echo "[fake mv4] 模拟第 3 次失败" >&2
  exit 1
fi
exec /bin/mv "$@"
FAKEMV4
chmod +x "$WORK/fakebin/mv4"
mkdir -p "$WORK/fakebin4"
cp "$WORK/fakebin/mv4" "$WORK/fakebin4/mv"
chmod +x "$WORK/fakebin4/mv"

SRC4="$WORK/src4"; DST4="$WORK/dst4"
mksrc "$SRC4" partial
mkdir -p "$DST4"
echo "OLD-py"  > "$DST4/playwrightmcp.py"
# 故意不建 requirements.txt
echo "OLD-pkg" > "$DST4/package.json"

rm -f /tmp/pw_fake_mv4_count
out4=$( PATH="$WORK/fakebin4:$PATH" commit_keepdeps_files "$SRC4" "$DST4" 2>&1 )
rc4=$?
check "用例4 退出码非 0" "$([ "$rc4" != 0 ] && echo yes || echo no)" "yes"
check "用例4 py 已恢复旧版" "$(cat "$DST4/playwrightmcp.py" 2>/dev/null || echo '<缺失>')" "OLD-py"
check "用例4 新建的 req 已被删除" "$([ -f "$DST4/requirements.txt" ] && echo present || echo absent)" "absent"
check "用例4 pkg 保持旧版" "$(cat "$DST4/package.json" 2>/dev/null || echo '<缺失>')" "OLD-pkg"
check "用例4 无 .old 残留（回滚全部成功）" "$(ls "$DST4"/*.old.* 2>/dev/null | wc -l)" "0"
check "用例4 无 .tmp 残留" "$(ls "$DST4"/*.tmp.* 2>/dev/null | wc -l)" "0"
check "用例4 无「回滚未完成」误报" "$(printf '%s' "$out4" | grep -c '回滚未完成')" "0"

rm -f /tmp/pw_fake_mv_count /tmp/pw_fake_mv3_count /tmp/pw_fake_mv4_count
echo
echo "keep-deps 回滚测试: PASS=$PASS FAIL=$FAILN"
[ "$FAILN" = 0 ]
