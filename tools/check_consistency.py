#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""仓库一致性自检（CI 与本地通用）。

用法：
    python3 tools/check_consistency.py [仓库根目录]

检查项：
  1. 语法：python / shell / json / workflow yaml
  2. 版本号一致性（package.json · config · CHANGELOG 首条 · README 徽章与下载名 · market/README 示例）
  3. 环境变量对照（代码 ⇄ 转发器 docstring ⇄ DEPLOY 环境变量表）
  4. 禁用命令扫描（`install chromium` —— 白名单：CHANGELOG、注释行）
  5. Markdown 锚点（`](#x)` 需在同文件或目标文件有对应定义）→ 仅 WARN
  6. 敏感信息扫描（ghp_ / github_pat_ / gho_ / ghs_ / ghr_）

退出码：有 FAIL 时为 1。
"""
from __future__ import annotations

import ast
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
FAILS: list[str] = []
WARNS: list[str] = []

# 扫描时统一跳过的目录（三个扫描节共用；此前各处自写，版本兜底里还带过
# 一个本地习惯的 MT2 —— 仓库里没有该目录，属历史遗留）
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv"}

# 自检工具文件豁免：检查器与负例夹具必然包含「被禁模式 / 示例 token / 示例版本」，
# 否则会自己抓自己（豁免是这类 self-check 脚本的标准做法，不削弱对业务代码的检查）
SKIP_FILES = {"tools/check_consistency.py", "tools/neg_cases.sh"}


def ok(msg: str) -> None:
    print(f"  \033[32mOK\033[0m   {msg}")


def fail(msg: str) -> None:
    print(f"  \033[31mFAIL\033[0m {msg}")
    FAILS.append(msg)


def warn(msg: str) -> None:
    print(f"  \033[33mWARN\033[0m {msg}")
    WARNS.append(msg)


def read(rel: str) -> str:
    path = os.path.join(ROOT, rel)
    if not os.path.isfile(path):
        return ""
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def section(title: str) -> None:
    print(f"\n== {title} ==")


def _ver_tuple(text: str) -> tuple[int, ...]:
    r"""版本号按前 3 段归一后再比较。

    契约：只接受 digits.digits.digits 形式的字符串（所有调用点均来自
    re.findall(r"v(\d+\.\d+\.\d+)", ...)）；传入其他形式会抛 ValueError。
    归一原因是 (1, 0, 0) < (1, 0, 0, 0) 为 True（元组逐元素比较的意外结果）。
    """
    parts = text.split(".")[:3]
    while len(parts) < 3:
        parts.append("0")
    return tuple(int(p) for p in parts)


# ------------------------------------------------------------------ 1. 语法
section("1. 语法")
py = "scripts/playwright_mcp.py"
if os.path.isfile(os.path.join(ROOT, py)):
    r = subprocess.run([sys.executable, "-m", "py_compile",
                        os.path.join(ROOT, py)],
                       capture_output=True, text=True)
    ok("python 语法") if r.returncode == 0 else fail(f"python 语法：{r.stderr.strip()[:200]}")
else:
    fail(f"缺少 {py}")

for sh in ("install.sh", "uninstall.sh"):
    if os.path.isfile(os.path.join(ROOT, sh)):
        r = subprocess.run(["bash", "-n", os.path.join(ROOT, sh)],
                           capture_output=True, text=True)
        ok(f"shell 语法 {sh}") if r.returncode == 0 else fail(f"{sh}：{r.stderr.strip()[:200]}")

for js in ("package.json", "config/mcp_config.json"):
    try:
        json.loads(read(js))
        ok(f"JSON {js}")
    except Exception as exc:  # noqa: BLE001
        fail(f"{js} 解析失败：{exc}")

wfdir = os.path.join(ROOT, ".github", "workflows")
if os.path.isdir(wfdir):
    for name in sorted(os.listdir(wfdir)):
        if not name.endswith((".yml", ".yaml")):
            continue
        try:
            import yaml  # 仅当环境有 PyYAML 时检查
        except ImportError:
            warn("未安装 PyYAML，跳过 workflow 语法检查")
            break
        try:
            yaml.safe_load(read(f".github/workflows/{name}"))
            ok(f"workflow yaml {name}")
        except Exception as exc:  # noqa: BLE001
            fail(f"workflow {name} 解析失败：{exc}")

# ------------------------------------------------------------------ 2. 版本号
section("2. 版本号一致性")
try:
    ver = json.loads(read("package.json"))["version"]
except Exception:  # noqa: BLE001
    ver = ""

if not ver:
    fail("无法从 package.json 读取版本号")
else:
    ok(f"基准版本（package.json）= {ver}")

    if f'"version": "{ver}"' in read("config/mcp_config.json"):
        ok("config/mcp_config.json 版本一致")
    else:
        fail("config/mcp_config.json 版本与 package.json 不一致")

    cl = read("CHANGELOG.md")
    first = None
    for line in cl.splitlines():
        # 跳过 Unreleased 段（发布前它本来就该在最新版本之上）；兼容 `## vX.Y.Z`
        m = re.match(r"^##\s*\[?v?(\d+\.\d+\.\d+)\]?", line.strip())
        if m:
            first = m.group(1)
            break
    if first == ver:
        ok(f"CHANGELOG 首条版本 = {ver}（已跳过 Unreleased）")
    else:
        fail(f"CHANGELOG 首条版本 = {first or '未找到'}（期望 {ver}）")

    rm = read("README.md")
    if f"badge/version-{ver}-" in rm:
        ok("README version 徽章一致")
    else:
        badge = re.search(r"badge/version-([\d.]+)-", rm)
        fail(f"README 徽章 = {badge.group(1) if badge else '未找到'}（期望 {ver}）")

    if f"playwright-mcp-for-operit-v{ver}.zip" in rm:
        ok("README 下载文件名一致")
    else:
        fail(f"README 下载文件名未指向 v{ver}")

    mk = read("market/README.md")
    if mk:
        # 只检查「当前版本语义」的位置，避免把历史叙述（如「自 v1.0.5 起」）误判为过期
        expected = (re.findall(r'Release（如 `v([\d.]+)`）', mk)
                    + re.findall(r'"version":\s*"([\d.]+)"', mk)
                    + re.findall(r"badge/version-([\d.]+)-", mk))
        stale = sorted({s for s in expected if s != ver and s != "1.0.0"})
        if stale:
            fail(f"market/README.md 出现过期版本号：{', '.join(stale)}（期望 {ver}）")
        else:
            ok(f"market/README.md 当前版本语义一致（检查 {len(expected)} 处）")

    # 兜底：全仓扫「带 v 前缀的版本号」，对照 CHANGELOG 自动收集的历史版本。
    # 不依赖任何中文措辞 —— 文案怎么改字都不会静默失效（r2 review 的核心担忧）。
    #
    # 已知边界（都有意为之）：
    #   · 只扫带 v 前缀的版本；裸版本（正文写 1.5.0）不在范围，以免误伤依赖版本
    #   · allow 从 CHANGELOG 正文抽取，偏松：叙述里提到的版本也算「已知」
    #   · floor 依赖「X.Y.Z 及更早」措辞（已兼容 及以前/及之前/截至）
    allow_ver = {ver} | set(re.findall(r"^#{2,3}\s*\[?v?(\d+\.\d+\.\d+)\]?", cl, re.M))
    allow_ver |= set(re.findall(r"\bv(\d+\.\d+\.\d+)\b", cl))
    # 外部依赖版本（如 @playwright/mcp 0.0.82）不是本仓库版本
    try:
        pkg = json.loads(read("package.json"))
        for field in ("dependencies", "devDependencies", "peerDependencies", "engines"):
            for val in (pkg.get(field) or {}).values():
                allow_ver |= set(re.findall(r"(\d+\.\d+\.\d+)", str(val)))
    except Exception:  # noqa: BLE001
        pass
    # CHANGELOG 若声明「X.Y.Z 及更早」已合并记录，则低于它的版本都视为已知历史
    merged = re.search(r"^##\s*\[?v?(\d+\.\d+\.\d+)\]?\s*(?:及更早|及以前|及之前|截至)", cl, re.M)
    floor = _ver_tuple(merged.group(1)) if merged else None
    scan_ext = {".md", ".py", ".sh", ".json", ".yml", ".yaml", ".js", ".ts", ".txt"}
    strange: set[str] = set()
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if os.path.splitext(name)[1].lower() not in scan_ext:
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT)
            if rel in SKIP_FILES:
                continue  # 检查器/夹具自身（含示例版本号）
            try:
                if os.path.getsize(path) > 2 * 1024 * 1024:
                    continue
                text = open(path, encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            for m in re.finditer(r"\bv(\d+\.\d+\.\d+)\b", text):
                found_v = m.group(1)
                if found_v in allow_ver:
                    continue
                if floor and _ver_tuple(found_v) < floor:
                    continue  # 低于「及更早」下界的版本，视为已知历史
                strange.add(f"v{found_v} @ {rel}")
    if strange:
        shown = ", ".join(sorted(strange)[:6])
        warn(f"出现 CHANGELOG 未记录过的版本号（{len(strange)} 处）：{shown}")
    else:
        ok("全仓 v 前缀版本号均在当前版本或 CHANGELOG 历史范围内")

def _env_call_target(call: ast.Call, os_aliases: set[str],
                     environ_aliases: set[str], getenv_aliases: set[str]):
    """判断是否为环境变量读取调用，返回 (来源描述, 第一个实参节点)。

    别名已归一：`import os as _os` / `from os import environ as E` / `getenv as g`
    都能识别（r2 外部 review 提出的缺口）。
    """
    func = call.func
    if isinstance(func, ast.Attribute) and func.attr in ("get", "pop", "setdefault"):
        base = func.value
        if ((isinstance(base, ast.Attribute) and base.attr in environ_aliases)
                or (isinstance(base, ast.Name) and base.id in environ_aliases)):
            return "os.environ", (call.args[0] if call.args else None)
    # 注：Alias 只可能来自 `from os import getenv as g`（此时 func 是 Name，
    # 由下方第三支处理）；这里的 Attribute 分支实际只匹配 X.getenv(...) 形式。
    if isinstance(func, ast.Attribute) and func.attr in getenv_aliases:
        if isinstance(func.value, ast.Name) and func.value.id in os_aliases:
            return "os.getenv", (call.args[0] if call.args else None)
    if isinstance(func, ast.Name) and func.id in getenv_aliases:
        return "getenv", (call.args[0] if call.args else None)
    return None, None


def _env_aliases(tree: ast.AST):
    """收集 import 别名集合。"""
    os_aliases, environ_aliases, getenv_aliases = {"os"}, {"environ"}, {"getenv"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for a in node.names:
                if a.name.split(".")[0] == "os":
                    os_aliases.add(a.asname or "os")
        elif isinstance(node, ast.ImportFrom) and node.module == "os":
            for a in node.names:
                target = a.asname or a.name
                if a.name == "environ":
                    environ_aliases.add(target)
                elif a.name == "getenv":
                    getenv_aliases.add(target)
    return os_aliases, environ_aliases, getenv_aliases


def _env_wrappers(tree: ast.AST, os_aliases, environ_aliases, getenv_aliases) -> set[str]:
    """自动发现「封装转发」函数：def f(name): return os.environ.get(name)。

    初始集仅作启发式种子（覆盖常见的 _int_env 等命名）；真正的识别靠
    自动发现，新增封装无需改本文件（r2 review 缺口 3/4）。
    """
    wrappers = {"_int_env", "_env", "_str_env", "_bool_env"}
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) or not node.args.args:
            continue
        param = node.args.args[0].arg
        for sub in ast.walk(node):
            if not isinstance(sub, ast.Call):
                continue
            _, arg = _env_call_target(sub, os_aliases, environ_aliases, getenv_aliases)
            if isinstance(arg, ast.Name) and arg.id == param:
                wrappers.add(node.name)
                break
    return wrappers


def collect_env_vars(tree: ast.AST):
    """用 AST 收集「真实读取」的环境变量，返回 (静态可确认集合, 动态读取位置列表)。

    静态不可解的情况（配置表迭代、f-string 拼接、跨模块变量名）无法枚举，
    会以 WARN 形式暴露在 CI 输出里，而不是假装覆盖完备。
    """
    os_aliases, environ_aliases, getenv_aliases = _env_aliases(tree)
    wrappers = _env_wrappers(tree, os_aliases, environ_aliases, getenv_aliases)

    # 只有当封装函数「确实被字面量调用过」时，其函数体内的动态实参才由调用处负责，
    # 这里跳过以免重复告警；否则（例如定义后从未被调用的函数）必须照常告警 ——
    # 否则动态读取会被静默吞掉（负例测试暴露的缺陷）。
    literal_called: set[str] = set()
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id in wrappers and node.args
                and isinstance(node.args[0], ast.Constant)
                and isinstance(node.args[0].value, str)):
            literal_called.add(node.func.id)
    wrapper_lines: set[int] = set()
    for node in ast.walk(tree):
        if (isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
                and node.name in literal_called):
            for sub in ast.walk(node):
                wrapper_lines.add(getattr(sub, "lineno", -1))

    found: set[str] = set()
    dynamic: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            src, arg = _env_call_target(node, os_aliases, environ_aliases, getenv_aliases)
            if src is None:
                func = node.func
                if isinstance(func, ast.Name) and func.id in wrappers:
                    src = func.id
                    arg = node.args[0] if node.args else None
            if src is None:
                continue
            if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                found.add(arg.value)
            elif node.lineno not in wrapper_lines:
                dynamic.append(f"L{node.lineno} {src}(非字面量)")
        elif isinstance(node, ast.Subscript):
            base, sl = node.value, node.slice
            if (isinstance(sl, ast.Constant) and isinstance(sl.value, str)
                    and ((isinstance(base, ast.Attribute) and base.attr in environ_aliases)
                         or (isinstance(base, ast.Name) and base.id in environ_aliases))):
                found.add(sl.value)
    return {v for v in found if re.fullmatch(r"[A-Z][A-Z0-9_]*", v)}, dynamic


def deploy_env_table(text: str):
    """截取 DEPLOY.md 的「环境变量表」区块，返回 (区块内容, 是否找到表头)。

    表头按「以 | 变量 开头」放宽匹配（列名微调不会失效）；找不到时由调用方 WARN，
    而不是返回空串静默把全部变量判成缺失（r2 review 指出的小瑕疵）。
    """
    m = re.search(r"(?m)^\|\s*变量.*$", text)
    if not m:
        return "", False
    rest = text[m.start():]
    nxt = re.search(r"\n##\s", rest[1:])
    return (rest if not nxt else rest[: nxt.start() + 1]), True


def _mentions(text: str, var: str) -> bool:
    """变量名是否在文本中出现（词边界匹配）。

    不用子串 `in`：否则 `PW_MCP_FOO_BAR` 会让代码里的 `PW_MCP_FOO` 误判为已覆盖。
    """
    return re.search(r"\b" + re.escape(var) + r"\b", text) is not None


# ------------------------------------------------------------------ 3. 环境变量
section("3. 环境变量对照（代码 ⇄ docstring ⇄ DEPLOY 表）")
code = read("scripts/playwright_mcp.py")
tree = ast.parse(code)  # 语法已在第 1 节校验过
docstring = ast.get_docstring(tree) or ""
deploy = read("docs/DEPLOY.md")

# 只统计「真实代码读取」的环境变量：AST 而非正则
# （正则会把注释/docstring 里的伪调用算进来，还会漏 os.getenv / os.environ["X"]）
env_read, dynamic_env = collect_env_vars(tree)
if dynamic_env:
    warn("存在动态环境变量读取（静态无法核对，需人工确认）：" + ", ".join(dynamic_env[:5]))

# DEPLOY 只在其「环境变量表」区块内匹配，避免正文随口提一句就算覆盖
table, table_found = deploy_env_table(deploy)
if not table_found:
    warn("未在 DEPLOY.md 找到「环境变量表」表头（| 变量 …），该检查已跳过")

missing_doc = sorted(v for v in env_read if not _mentions(docstring, v))
if missing_doc:
    fail(f"docstring 未说明的环境变量：{', '.join(missing_doc)}")
else:
    ok(f"docstring 覆盖全部 {len(env_read)} 个环境变量")

if not table_found:
    pass
else:
    missing_deploy = sorted(v for v in env_read if not _mentions(table, v))
    if missing_deploy:
        fail(f"DEPLOY 环境变量表缺：{', '.join(missing_deploy)}")
    else:
        ok(f"DEPLOY 表覆盖全部 {len(env_read)} 个环境变量")

# 跨文件契约：单测备份/恢复的键应覆盖转发器读取的全部环境变量
# （否则外部环境残留会悄悄污染测试，见 r4 review ⑤；
#   仅覆盖 tests/test_find_chrome.py —— 将来新增做环境备份的测试文件请同步此处）
tst = read("tests/test_find_chrome.py")
m = re.search(r"ENV_KEYS = \(([^)]*)\)", tst, re.S)
if not tst:
    warn("未找到 tests/test_find_chrome.py，ENV_KEYS 漂移检查已跳过")
elif not m:
    warn("tests/test_find_chrome.py 中未匹配到 ENV_KEYS = (...)，漂移检查已跳过")
else:
    # 提取括号内所有大写标识符：同时兼容 ' 与 " 两种引号风格
    test_keys = set(re.findall(r"[A-Z_]{4,}", m.group(1)))
    drift = sorted(env_read - test_keys)
    if drift:
        warn(f"tests/test_find_chrome.py 的 ENV_KEYS 未覆盖：{', '.join(drift)}（环境变量集可能漂移）")
    else:
        ok(f"ENV_KEYS 覆盖全部 {len(env_read)} 个环境变量")

# ------------------------------------------------------------------ 4. 禁用命令
section("4. 禁用命令扫描（install chromium）")
bad_hits: list[str] = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for name in filenames:
        if not name.endswith((".py", ".sh", ".md", ".json", ".yml", ".yaml", ".txt")):
            continue
        rel = os.path.relpath(os.path.join(dirpath, name), ROOT)
        if rel in SKIP_FILES:
            continue  # 检查器/夹具自身
        if rel == "CHANGELOG.md":
            continue  # 变更记录里描述历史问题属正常
        try:
            for i, line in enumerate(open(os.path.join(dirpath, name), encoding="utf-8"), 1):
                if "install chromium" not in line:
                    continue
                if "install-browser" in line or line.lstrip().startswith("#"):
                    continue
                bad_hits.append(f"{rel}:{i}")
        except OSError:
            continue
if bad_hits:
    fail(f"出现旧命令 `install chromium`：{', '.join(bad_hits)}")
else:
    ok("未出现旧命令（CHANGELOG 与注释已白名单）")

# ------------------------------------------------------------------ 5. 锚点
section("5. Markdown 锚点（仅告警）")
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for name in filenames:
        if not name.endswith(".md"):
            continue
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, ROOT)
        text = open(path, encoding="utf-8").read()
        own_ids = set(re.findall(r'<a\s+id="([^"]+)"', text))
        for target, anchor in re.findall(r"\]\(([^)\s#]*)#([^)\s]+)\)", text):
            if not target:
                if anchor not in own_ids and anchor not in text.replace(" ", "-"):
                    warn(f"{rel}：锚点 #{anchor} 疑似无定义")
                continue
            tpath = os.path.join(os.path.dirname(path), target)
            if not os.path.isfile(tpath):
                continue
            ttext = open(tpath, encoding="utf-8").read()
            if anchor in set(re.findall(r'<a\s+id="([^"]+)"', ttext)):
                continue
            warn(f"{rel}：跨文件锚点 #{anchor} 在 {target} 中未找到 <a id>")

# ------------------------------------------------------------------ 6. 敏感信息
section("6. 敏感信息扫描")
secret = re.compile(r"(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gho_[A-Za-z0-9]{20,}|ghs_[A-Za-z0-9]{20,}|ghr_[A-Za-z0-9]{20,})")
leak: list[str] = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for name in filenames:
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, ROOT)
        if rel in SKIP_FILES:
            continue  # 检查器/夹具自身（含示例 token 模式）
        try:
            if os.path.getsize(path) > 2 * 1024 * 1024:
                continue
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        if secret.search(text):
            leak.append(rel)
if leak:
    fail(f"疑似 token 泄露：{', '.join(sorted(set(leak)))}")
else:
    ok("未发现 token 泄露")

# ------------------------------------------------------------------ 汇总
print()
print("=" * 52)
print(f"FAIL {len(FAILS)} · WARN {len(WARNS)}")
for f in FAILS:
    print("  ✗ " + f)
for w in WARNS:
    print("  ! " + w)
print("=" * 52)
sys.exit(1 if FAILS else 0)