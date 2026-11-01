#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""升级回归：主配置里带着旧版插件 ID（playwright_mcp）时，
安装脚本合并后应当只剩新 ID，其它插件原样保留。

同时确保合并逻辑升级时不会误伤用户的其它 MCP 插件。
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MERGE_MARKER = 'node - "$MAIN_CFG" "$SEG_FILE" <<\'NODE\''


def extract_merge_js():
    """从 install.sh 里抽出真实的合并逻辑（第二段 node heredoc）。"""
    with open(os.path.join(ROOT, "install.sh"), encoding="utf-8") as f:
        text = f.read()
    i = text.index(MERGE_MARKER)
    start = text.index("\n", i) + 1
    end = text.index("\nNODE\n", start)
    return text[start:end]


@unittest.skipUnless(shutil.which("node"), "需要 node")
class TestLegacyIdMigration(unittest.TestCase):
    """装过 1.0.8 及更早版本的用户，主配置里会留着 playwright_mcp 这个旧 ID。"""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.js = os.path.join(self.tmp, "merge.js")
        with open(self.js, "w", encoding="utf-8") as f:
            f.write(extract_merge_js())

    def _merge(self, main_data, seg_data):
        main_p = os.path.join(self.tmp, "main.json")
        seg_p = os.path.join(self.tmp, "seg.json")
        with open(main_p, "w", encoding="utf-8") as f:
            json.dump(main_data, f, ensure_ascii=False)
        with open(seg_p, "w", encoding="utf-8") as f:
            json.dump(seg_data, f, ensure_ascii=False)
        r = subprocess.run(["node", self.js, main_p, seg_p],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, "合并失败：\n" + r.stderr + r.stdout)
        with open(main_p, encoding="utf-8") as f:
            return json.load(f)

    def test_legacy_id_removed_others_kept(self):
        """老用户升级：旧 ID 要清掉，新 ID 要进来，别的插件不能动。"""
        main = {
            "mcpServers": {
                "playwright_mcp": {"command": "old"},
                "other_mcp": {"command": "keep"},
            },
            "pluginMetadata": {
                "playwright_mcp": {"name": "old"},
                "other_mcp": {"name": "keep"},
            },
        }
        seg = {
            "mcpServers": {"playwrightmcp": {"command": "new"}},
            "pluginMetadata": {"playwrightmcp": {"name": "new"}},
        }
        d = self._merge(main, seg)
        self.assertNotIn("playwright_mcp", d["mcpServers"], "旧 ID 还留在 mcpServers 里")
        self.assertNotIn("playwright_mcp", d["pluginMetadata"], "旧 ID 还留在 pluginMetadata 里")
        self.assertEqual(d["mcpServers"]["playwrightmcp"]["command"], "new")
        self.assertEqual(d["pluginMetadata"]["playwrightmcp"]["name"], "new")
        self.assertEqual(d["mcpServers"]["other_mcp"]["command"], "keep", "别的插件被误伤")
        self.assertEqual(d["pluginMetadata"]["other_mcp"]["name"], "keep", "别的插件被误伤")

    def test_clean_config_untouched(self):
        """全新安装（配置里本来就没有旧 ID）不该受影响。"""
        main = {
            "mcpServers": {"other_mcp": {"command": "keep"}},
            "pluginMetadata": {},
        }
        seg = {
            "mcpServers": {"playwrightmcp": {"command": "new"}},
            "pluginMetadata": {"playwrightmcp": {"name": "new"}},
        }
        d = self._merge(main, seg)
        self.assertEqual(d["mcpServers"]["other_mcp"]["command"], "keep")
        self.assertEqual(d["mcpServers"]["playwrightmcp"]["command"], "new")


if __name__ == "__main__":
    unittest.main()
