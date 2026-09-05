#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Playwright MCP 转发器（Operit 新版机制：python -m playwright_mcp → exec 全局 playwright MCP cli）

对齐 Operit 源码（MCPConfigGenerator.kt）：PYTHON 项目用 venv/bin/python -m <模块名> 启动，
env 不传（Operit 不强求），路径硬编码在转发器内（install.sh 部署时替换占位符为真实路径）。

手动部署时：把本文件放到 Android 源目录（如 /sdcard/Download/Operit/mcp_plugins/playwright_mcp/），
并把下面三个占位符改成你机器的真实路径。"""
import os
import sys

# 占位符由 install.sh 部署时替换为真实路径（NODE/CLI/CHROME）
NODE = "@NODE_BIN@"
CLI = "@CLI_JS@"
CHROME = "@CHROME_BIN@"

os.execv(NODE, [NODE, CLI, "--headless", "--no-sandbox", "--executable-path", CHROME] + sys.argv[1:])