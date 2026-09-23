#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/playwright_mcp.py 的 find_chrome() 边界单元测试。

只依赖标准库（unittest / importlib / tempfile），可直接：
    python -m unittest discover -s tests -v

覆盖 4 种情形：
  1. 默认（PW_MCP_PREFERRED_BUILD 未设）      → 优先 1237
  2. PW_MCP_PREFERRED_BUILD=0                 → 关闭偏好，退回「选最大 build」
  3. PW_MCP_PREFERRED_BUILD=9999（本机没有）   → 优雅回落「选最大 build」
  4. PW_MCP_PREFERRED_BUILD=abc（非法值）      → 告警并回退默认 1237

说明：断言只比较 chromium-<build> 目录名（不比较绝对路径），
这样即使本机 ~/.cache/ms-playwright 里已有真实 build，断言依然成立。
"""
from __future__ import annotations

import importlib.util
import os
import shutil
import tempfile
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FORWARDER = os.path.join(REPO_ROOT, "scripts", "playwright_mcp.py")

# 与转发器 import 期可能读取的键保持同步；未备份的键会污染进程环境。
# 注：HOME 也在受管键内 —— setUp 会将其清空；若将来新增依赖 HOME 的用例，
#     请在 _find_chrome(HOME=...) 里显式传入（当前用例经 PLAYWRIGHT_BROWSERS_PATH 绕过）。
ENV_KEYS = ("PW_MCP_PREFERRED_BUILD", "PW_MCP_MIN_BUILD", "PW_MCP_LOG_MAX",
            "PW_MCP_SKIP_INSTALL", "PW_MCP_AUTO_DOWNLOAD", "PW_MCP_AUTO_INSTALL",
            "PW_MCP_EXTRA_ARGS", "PW_MCP_NPM_REGISTRY", "PW_MCP_VER",
            "NODE_BIN", "PLAYWRIGHT_BROWSERS_PATH", "PLAYWRIGHT_CHROME_BIN",
            "PLAYWRIGHT_DOWNLOAD_HOST", "HOME")


def load_forwarder():
    """每次重新加载模块（环境变量在 import 时求值，必须 per-case 加载）。"""
    spec = importlib.util.spec_from_file_location("fwd_under_test", FORWARDER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build_name(path: str) -> str:
    """从 .../chromium-1237/chrome-linux/chrome 取出 chromium-1237。"""
    if not path:
        return ""
    return os.path.basename(os.path.dirname(os.path.dirname(path)))


class FindChromeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="pw-mcp-test-")
        for build in (1237, 1246, 1300):
            directory = os.path.join(cls.tmp, f"chromium-{build}", "chrome-linux")
            os.makedirs(directory, exist_ok=True)
            # 转发器会过滤 <=1MB 的残缺文件，所以造 2MB 假的 chrome
            with open(os.path.join(directory, "chrome"), "wb") as fh:
                fh.write(b"\0" * (2 * 1024 * 1024))
        cls.backup = {k: os.environ.get(k) for k in ENV_KEYS}
        # 环境基线统一由 setUp 逐 case 设置（此处不再重复设置）

    @classmethod
    def tearDownClass(cls):
        for key, value in cls.backup.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def setUp(self):
        """每个 case 从干净基线开始：清掉全部受管键（含外部环境残留）。"""
        for key in ENV_KEYS:
            os.environ.pop(key, None)
        os.environ["PLAYWRIGHT_BROWSERS_PATH"] = self.tmp

    def _find_chrome(self, **env):
        for key, value in env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = str(value)
        return load_forwarder().find_chrome()

    def test_default_prefers_1237(self):
        """默认应优先已知可用 build 1237（即使本机还有 1246/1300）。"""
        got = self._find_chrome(PW_MCP_PREFERRED_BUILD=None)
        self.assertEqual(build_name(got), "chromium-1237", f"got={got}")

    def test_preferred_zero_falls_back_to_highest(self):
        """设 0 关闭偏好 → 回到「选最大 build」。"""
        got = self._find_chrome(PW_MCP_PREFERRED_BUILD=0)
        self.assertEqual(build_name(got), "chromium-1300", f"got={got}")

    def test_preferred_absent_build_falls_back(self):
        """偏好 build 本机不存在 → 优雅回落到「选最大」。"""
        got = self._find_chrome(PW_MCP_PREFERRED_BUILD=9999)
        self.assertEqual(build_name(got), "chromium-1300", f"got={got}")

    def test_preferred_invalid_falls_back_to_default(self):
        """非法值 → _int_env 告警并回退默认 1237。"""
        got = self._find_chrome(PW_MCP_PREFERRED_BUILD="abc")
        self.assertEqual(build_name(got), "chromium-1237", f"got={got}")


if __name__ == "__main__":
    unittest.main(verbosity=2)