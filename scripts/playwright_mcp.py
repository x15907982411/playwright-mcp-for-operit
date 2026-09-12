#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Playwright MCP for Operit —— 自举转发器 (v1.0.5)

设计目标：无论从 Operit 市场（自动 npm install）还是手动解压安装，
首次启动都能自己把依赖补齐，做到真正的「装完即用」。

启动流程：
  1. 定位 node（PATH / NODE_BIN）
  2. 定位 @playwright/mcp 的 cli.js：
       ① 插件目录内 node_modules（市场 npm install 产物 / 手动 npm i 产物）
       ② 全局 npm root -g
       ③ 都没有 → 自动 npm i（本地优先，失败回退全局）
  3. 定位 Chromium（headless）：
       ① PLAYWRIGHT_CHROME_BIN 环境变量
       ② ~/.cache/ms-playwright 与 /root/.cache/ms-playwright（多路径 + 非空 + build 校验）
       ③ 都没有 → 自动下载（node cli.js install chromium）
  4. exec 到 node cli.js --headless --no-sandbox --executable-path <chrome>

环境变量（均可选）：
  NODE_BIN                 指定 node 可执行文件
  PLAYWRIGHT_CHROME_BIN    指定 Chromium 可执行文件
  PW_MCP_VER               MCP 版本，默认 0.0.80
  PW_MCP_MIN_BUILD         期望的 chromium build，默认 1243（低于此值仅告警不报错）
  PW_MCP_AUTO_INSTALL      0 = 不自动安装 MCP 包
  PW_MCP_AUTO_DOWNLOAD     0 = 不自动下载 Chromium
  PW_MCP_NPM_REGISTRY      指定 npm registry（例如国内镜像）
  PW_MCP_EXTRA_ARGS        追加给 MCP server 的参数，空格分隔

诊断日志全部输出到 stderr（Operit 日志可见），且同步落盘到插件目录下的
bootstrap.log，便于用户事后排查。
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time

MCP_PKG = "@playwright/mcp"
MCP_VER = os.environ.get("PW_MCP_VER", "0.0.80")
MIN_CHROMIUM_BUILD = int(os.environ.get("PW_MCP_MIN_BUILD", "1243"))
HERE = os.path.dirname(os.path.abspath(__file__))
LOG_PATH = os.path.join(HERE, "bootstrap.log")


# ---------------------------------------------------------------- 日志

def _stamp() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def log(msg: str, level: str = "INFO") -> None:
    line = f"[{_stamp()}][{level}] {msg}"
    print(f"[playwright_mcp] {msg}", file=sys.stderr, flush=True)
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


def die(msg: str, hint: str = "") -> None:
    log(msg, "ERROR")
    if hint:
        log(hint, "HINT")
    print(f"\n[playwright_mcp] 启动失败：{msg}", file=sys.stderr, flush=True)
    if hint:
        print(f"[playwright_mcp] 建议：{hint}", file=sys.stderr, flush=True)
    print("[playwright_mcp] 详细日志见插件目录 bootstrap.log", file=sys.stderr, flush=True)
    sys.exit(1)


# ---------------------------------------------------------------- 查找

def find_node() -> str | None:
    env_bin = os.environ.get("NODE_BIN")
    candidates = [env_bin] if env_bin else []
    candidates += [
        shutil.which("node"),
        "/usr/bin/node",
        "/usr/local/bin/node",
        os.path.expanduser("~/.local/bin/node"),
    ]
    for cand in candidates:
        if cand and os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return None


def run(cmd: list[str], timeout: int = 900, env: dict | None = None) -> subprocess.CompletedProcess:
    merged = os.environ.copy()
    if env:
        merged.update(env)
    return subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
        env=merged,
    )


def npm_registry_args() -> list[str]:
    registry = os.environ.get("PW_MCP_NPM_REGISTRY")
    return ["--registry", registry] if registry else []


def find_mcp_cli(node: str) -> tuple[str | None, str]:
    """返回 (cli.js 路径, 来源描述)。检查顺序：插件内 → 全局。"""
    local = os.path.join(HERE, "node_modules", MCP_PKG, "cli.js")
    if os.path.isfile(local):
        return local, "插件本地 node_modules"

    roots: list[str] = []
    try:
        proc = run(["npm", "root", "-g"], timeout=30)
        if proc.stdout.strip():
            roots.append(proc.stdout.strip().splitlines()[-1].strip())
    except Exception:
        pass
    roots += [
        "/usr/lib/node_modules",
        "/usr/local/lib/node_modules",
        os.path.expanduser("~/.npm-global/lib/node_modules"),
    ]
    for root in roots:
        if not root:
            continue
        cand = os.path.join(root, MCP_PKG, "cli.js")
        if os.path.isfile(cand):
            return cand, f"全局 node_modules（{root}）"
    return None, "未找到"


def install_mcp(node: str) -> str | None:
    """自动安装 MCP 包（本地优先）。返回安装后的 cli.js 路径或 None。"""
    if os.environ.get("PW_MCP_AUTO_INSTALL", "1") == "0":
        return None

    spec = f"{MCP_PKG}@{MCP_VER}"
    log(f"未找到 {MCP_PKG}，开始自动安装（{spec}）……")

    # ① 插件本地安装（优先：随插件目录走，不污染全局）
    pkg_json = os.path.join(HERE, "package.json")
    if not os.path.isfile(pkg_json):
        try:
            with open(pkg_json, "w", encoding="utf-8") as fh:
                fh.write('{\n  "name": "playwright-mcp-for-operit-runtime",\n  "private": true\n}\n')
        except OSError:
            pass
    try:
        proc = run(["npm", "install", "--no-audit", "--no-fund", *npm_registry_args(), spec], timeout=900)
        if proc.returncode == 0:
            cli = os.path.join(HERE, "node_modules", MCP_PKG, "cli.js")
            if os.path.isfile(cli):
                log(f"本地安装成功：{cli}")
                return cli
        else:
            log(f"本地安装失败（exit={proc.returncode}）：{(proc.stdout or '')[-500:]}", "WARN")
    except Exception as exc:  # noqa: BLE001
        log(f"本地安装异常：{exc}", "WARN")

    # ② 全局安装（回退）
    log("尝试全局安装……")
    try:
        proc = run(["npm", "install", "-g", "--no-audit", "--no-fund", *npm_registry_args(), spec], timeout=900)
        if proc.returncode == 0:
            cli, src = find_mcp_cli(node)
            if cli:
                log(f"全局安装成功：{cli}（{src}）")
                return cli
        else:
            log(f"全局安装失败（exit={proc.returncode}）：{(proc.stdout or '')[-500:]}", "WARN")
    except Exception as exc:  # noqa: BLE001
        log(f"全局安装异常：{exc}", "WARN")
    return None


def _chrome_build(path: str) -> int:
    """从路径中提取 chromium build 号（如 chromium-1243），失败返回 0。"""
    parts = path.replace("\\", "/").split("/")
    for part in parts:
        if part.startswith("chromium-"):
            num = part.split("-", 1)[1]
            if num.isdigit():
                return int(num)
    return 0


def find_chrome() -> str | None:
    env_bin = os.environ.get("PLAYWRIGHT_CHROME_BIN")
    if env_bin and os.path.isfile(env_bin) and os.path.getsize(env_bin) > 1024 * 1024:
        return env_bin

    best: tuple[int, str] | None = None
    bases = [
        os.path.expanduser("~/.cache/ms-playwright"),
        "/root/.cache/ms-playwright",
        os.environ.get("PLAYWRIGHT_BROWSERS_PATH", ""),
    ]
    for base in bases:
        if not base or not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            if "chrome-linux" not in dirpath:
                continue
            for name in filenames:
                if name != "chrome":
                    continue
                full = os.path.join(dirpath, name)
                try:
                    if os.path.getsize(full) <= 1024 * 1024:  # 过滤残缺/空文件
                        continue
                except OSError:
                    continue
                build = _chrome_build(full)
                if best is None or build > best[0]:
                    best = (build, full)
            dirnames[:] = []  # 命中目录后不再深入
    return best[1] if best else None


def download_chrome(node: str, cli: str) -> str | None:
    if os.environ.get("PW_MCP_AUTO_DOWNLOAD", "1") == "0":
        return None
    log("未找到 Chromium，开始自动下载（约 150MB，首次可能耗时数分钟）……")
    env = {}
    host = os.environ.get("PLAYWRIGHT_DOWNLOAD_HOST")
    if host:
        env["PLAYWRIGHT_DOWNLOAD_HOST"] = host
    try:
        proc = run([node, cli, "install", "chromium"], timeout=1800, env=env)
        tail = (proc.stdout or "")[-800:]
        if proc.returncode != 0:
            log(f"Chromium 下载失败（exit={proc.returncode}）：{tail}", "WARN")
            return None
        log("Chromium 下载完成")
    except Exception as exc:  # noqa: BLE001
        log(f"Chromium 下载异常：{exc}", "WARN")
        return None
    return find_chrome()


# ---------------------------------------------------------------- 主流程

def main() -> None:
    log(f"自举启动（插件目录：{HERE}）")

    node = find_node()
    if not node:
        die(
            "未找到 node（需要 Node.js ≥ 18）",
            "请在 proot/终端安装：apt install -y nodejs npm（或使用 NODE_BIN 环境变量指定路径）",
        )
    log(f"node = {node}")

    cli, source = find_mcp_cli(node)
    if not cli:
        cli = install_mcp(node)
        if not cli:
            die(
                f"未找到且无法自动安装 {MCP_PKG}@{MCP_VER}",
                "手动安装：npm i -g @playwright/mcp@0.0.80（国内可加 --registry https://registry.npmmirror.com）；"
                "或设置 PW_MCP_AUTO_INSTALL=0 禁用自动安装后自行准备",
            )
    else:
        log(f"MCP CLI = {cli}（来源：{source}）")

    chrome = find_chrome()
    if chrome:
        build = _chrome_build(chrome)
        log(f"Chromium = {chrome}（build={build or '未知'}）")
        if build and build < MIN_CHROMIUM_BUILD:
            log(
                f"本机 Chromium build={build} 低于官方期望 {MIN_CHROMIUM_BUILD}，"
                "跨 build 实测兼容，若异常请执行: node <cli.js> install chromium",
                "WARN",
            )
    else:
        chrome = download_chrome(node, cli)
        if not chrome:
            die(
                "未找到且无法自动下载 Chromium",
                "可手动执行：node <MCP cli.js> install chromium；"
                "或设置 PLAYWRIGHT_CHROME_BIN 指向已有的 chrome 可执行文件",
            )

    args = [node, cli, "--headless", "--no-sandbox", "--executable-path", chrome]
    extra = os.environ.get("PW_MCP_EXTRA_ARGS", "").split()
    args += extra
    args += sys.argv[1:]

    log("启动 MCP server：" + " ".join(args[:3]) + " ...")
    try:
        os.execv(node, args)
    except OSError as exc:
        die(f"exec 启动失败：{exc}", "请确认 node 可执行且 cli.js 路径正确")


if __name__ == "__main__":
    main()
