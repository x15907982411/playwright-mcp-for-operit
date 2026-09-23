#!/bin/bash
# 一致性检查的负例回归：故意注入问题，验证检查脚本真的会抓到。
#
# 用法（本地与 CI 通用）：
#     bash tools/neg_cases.sh [仓库根目录]
# 不传参数时自动从脚本位置推导仓库根目录（<repo>/tools/neg_cases.sh → <repo>）。
#
# 设计要点（r3 review 采纳项）：
#   · 每个负例使用独立副本，互不污染
#   · 每次注入都断言「注入目标存在」，避免静默失败导致「假通过」
#   · 临时目录用 mktemp -d，支持并发运行

command -v python3 >/dev/null 2>&1 || { echo "python3 not found"; exit 1; }

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
CK="$ROOT/tools/check_consistency.py"
BASE="$ROOT"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

echo "仓库根目录 : $BASE"
echo "检查脚本   : $CK"
echo "临时目录   : $T"
echo

FAILED=0

reset_copy() {
  rm -rf "$T/repo"
  cp -a "$BASE" "$T/repo"
  # 副本不需要版本库与依赖目录，去掉可显著加快本地回归
  rm -rf "$T/repo/.git" "$T/repo/node_modules"
}

report() {  # report <名称> <期望FAIL数> <期望WARN数>
  local name="$1" want_f="$2" want_w="$3" line got_f got_w out
  out="$(python3 "$CK" "$T/repo" 2>&1)"
  # 锚定整行，避免未来失败消息里出现 "FAIL 3" 之类的子串被 tail -1 抓错
  line="$(echo "$out" | grep -aE '^FAIL [0-9]+ · WARN [0-9]+$' | tail -1)"
  if [ -z "$line" ]; then
    echo "  ✗ $name —— 检查脚本本身异常（无汇总行），末几行输出："
    echo "$out" | tail -3 | sed 's/^/      /'
    FAILED=1
    return
  fi
  got_f="$(echo "$line" | sed -n 's/.*FAIL \([0-9]*\).*/\1/p')"
  got_w="$(echo "$line" | sed -n 's/.*WARN \([0-9]*\).*/\1/p')"
  if [ "$got_f" = "$want_f" ] && [ "$got_w" = "$want_w" ]; then
    echo "  ✓ $name （FAIL $got_f · WARN $got_w）"
  else
    echo "  ✗ $name —— 期望 FAIL $want_f · WARN $want_w，实际：$line"
    # 排除汇总行；注意该「·」为 UTF-8 全角中间点（LANG=C 等环境可能匹配不到，仅影响详情展示）
    python3 "$CK" "$T/repo" 2>&1 | grep -aE '(FAIL|WARN)' | grep -avE 'FAIL [0-9]+ · WARN' | head -3 | sed 's/^/      /'
    FAILED=1
  fi
}

echo "① 正例：原样仓库（期望 FAIL 0 · WARN 0）"
reset_copy
report "正例" 0 0
echo

echo "② 陌生版本号 v9.9.9（期望 WARN 1）"
reset_copy
printf '参见 v%s 的说明。\n' '9.9.9' >> "$T/repo/README.md"
report "陌生版本号" 0 1
echo

echo "③ 未被调用的探针函数里做动态读取（期望 WARN 1）"
reset_copy
python3 - "$T/repo/scripts/playwright_mcp.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
target = "def main() -> None:"
assert target in s, "注入目标不存在：def main() -> None:"
probe = "def _probe_dynamic():\n    return os.environ.get(DYNAMIC_NAME)\n\n\n" + target
open(p, "w", encoding="utf-8").write(s.replace(target, probe, 1))
print("  注入生效")
PY
report "动态读取" 0 1
echo

echo "④ DEPLOY 表头改名（期望 WARN 1，且不是静默判全缺）"
reset_copy
BEFORE="$(grep -c '^| 变量 | 默认 | 作用 |' "$T/repo/docs/DEPLOY.md" || true)"
if [ "$BEFORE" -lt 1 ]; then
  echo "  ✗ 注入目标不存在：DEPLOY 表头（跳过本项）"
  FAILED=1
else
  sed -i 's/^| 变量 | 默认 | 作用 |/| 名称 | 默认 | 作用 |/' "$T/repo/docs/DEPLOY.md"
  report "DEPLOY 表头" 0 1
fi
echo

echo "⑤ docstring 里变量名被改成 ..._X（期望 FAIL 1）"
reset_copy
python3 - "$T/repo/scripts/playwright_mcp.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
head, sep, tail = s.partition('"""')
body, sep2, rest = tail.partition('"""')
assert "PW_MCP_PREFERRED_BUILD" in body, "注入目标不在 docstring 里"
body2 = body.replace("PW_MCP_PREFERRED_BUILD", "PW_MCP_PREFERRED_BUILD_X")
assert body2 != body, "替换未生效"
open(p, "w", encoding="utf-8").write(head + sep + body2 + sep2 + rest)
print("  注入生效")
PY
report "docstring 变量名" 1 0
echo

echo "⑥ install chromium 旧命令复活（期望 FAIL 1）"
reset_copy
echo 'CMD = "install chromium"' >> "$T/repo/scripts/playwright_mcp.py"
report "旧命令复活" 1 0
echo

# ⑦ 的 WARN 1 = 新变量名未同步到 test_find_chrome.py 的 ENV_KEYS（跨文件契约漂移）
echo "⑦ 代码里的环境变量名与 docstring 对不上（期望 FAIL 2 · WARN 1）"
reset_copy
python3 - "$T/repo/scripts/playwright_mcp.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
assert '"PW_MCP_MIN_BUILD"' in s, "注入目标不存在"
s2 = s.replace('"PW_MCP_MIN_BUILD"', '"PW_MCP_MIN_BUILD_ZZ"')
assert s2 != s, "替换未生效"
open(p, "w", encoding="utf-8").write(s2)
print("  注入生效")
PY
report "变量名不一致" 2 1
echo

echo "⑧ token 泄露（期望 FAIL 1）"
reset_copy
printf 'TOKEN=ghp_%s\n' 'abcdefghijklmnopqrstuvwxyz012345' >> "$T/repo/README.md"
report "token 泄露" 1 0
echo

echo "⑨ DEPLOY 表里删掉一个变量行（期望 FAIL 1）"
reset_copy
BEFORE="$(grep -c '^| `PW_MCP_LOG_MAX`' "$T/repo/docs/DEPLOY.md" || true)"
if [ "$BEFORE" -lt 1 ]; then
  echo "  ✗ 注入目标不存在：DEPLOY 中的 PW_MCP_LOG_MAX 行（跳过本项）"
  FAILED=1
else
  sed -i '/^| `PW_MCP_LOG_MAX`/d' "$T/repo/docs/DEPLOY.md"
  report "DEPLOY 缺变量" 1 0
fi
echo

if [ "$FAILED" = "0" ]; then
  echo "全部负例按预期触发 ✅"
else
  echo "存在未按预期触发的负例 ❌"
fi
exit "$FAILED"