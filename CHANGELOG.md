# Changelog

本插件遵循 [语义化版本](https://semver.org/lang/zh-CN/)，但请注意：**插件自身版本与上游 `@playwright/mcp` 版本是两条独立的版本线**。

## [1.1.0] - 2026-11-14

### 跟上上游 0.0.85

`@playwright/mcp` 从 0.0.84 升到 0.0.85，`playwright-core` 跟着从 `1.65.0-alpha-2026-10-30` 走到 `1.66.0-alpha-2026-11-09`。

这次上游动的东西，对 Operit 版来说大部分摸不到，但还是列一下：

- `--background`：配合 `--extension` 用时，控制的标签页不激活、浏览器窗口不抢焦点。需要浏览器扩展 0.5.0 以上
- `--no-tab-group`：配合 `--extension` 时，不把控制的标签页塞进 Playwright 自己的标签组。同样需要扩展 0.5.0 以上
- `browser.contextOptions.locateOnlyVisible`：新的配置项，开启后定位器只看可见元素，相当于自动给每个定位器加 `.filter({ visible: true })`。默认关
- `browser_snapshot` 现在会保留容器（对话框、地标、表格）的可访问名称，以前即使标题或 caption 就在眼前也可能显示为空
- 表单关联的自定义元素支持 `getByLabel` 了，原生的 `<label>` 关联以前对 `form-associated custom elements` 不生效

前两条是浏览器扩展专属，手机上的 Operit 用不到；后三条是全局生效的改进。

### 15 条修复，挑几个有意义的

- **回滚了 0.0.84 的 aria 可见性过滤**：inert 或 modal 对话框外的内容，`browser_snapshot` 不再因为这两个原因隐藏。点击、填写、选择仍然会等 inert 目标变成非 inert
- **配置文件里的相对路径改为「相对于源文件」解析**：profile、executable、storage-state、output 这些路径，以前按工作目录算，现在按配置文件所在目录算；符号链接则按目标文件所在目录。命令行参数和环境变量里的路径仍然按工作目录
- **页面定时器被节流或暂停时，settle 等待不再挂死**：这条对 Android 后台运行有实际价值，以前页面被系统压住时工具调用可能卡在那里
- **`browser_navigate` 不再把 HTTP 自动升级成 HTTPS**：内网或 HTTP 站点测试更准了
- `browser_evaluate` 现在能返回 `BigInt`、`NaN`、`Infinity`、`undefined` 和循环对象的可读表示，不再丢值或序列化失败
- `browser_console_messages` 的源行号改成从 1 开始（编辑器风格）
- `browser_take_screenshot` 的 `fullPage: true` 支持独立 SVG 文档了
- `--device` 传未知设备名会明确报错，也不再篡改共享的设备预设
- 页面和 context 监听器里抛出的异常，改为报成 console error，能在工具响应里看到

完整列表见上游 v0.0.85 的 release notes。

### Chromium 还是 1237

上游 0.0.85 配套的 Chromium 是 **1254**（Chrome for Testing 158.0.8127.18），比 0.0.84 那会儿的 1252 又跳了 2 个。

proot 环境里的红线不变：rev1246 以上一启动就是 SIGTRAP（exit 133）。所以 1237 继续留着，`PW_MCP_KNOWN_BAD_MIN=1246` 的拦截逻辑原样保留。

这次跨度更大，特意先把兼容性跑了一遍再动仓库：

- `playwright-core 1.66.0-alpha-2026-11-09` 驱动 `chromium-1237`（Chrome 152.0.7977.8），差 **17 个 build**
- launch 3.1 秒（冷启动）/ setContent / screenshot / evaluate / click / close 全通过，总耗时 4.9 秒
- 走真实 MCP 协议：initialize → tools/list → navigate → snapshot → screenshot → evaluate → close，全链路 **3.7 秒**
- `tools/list` 返回 **25 个**，跟 0.0.83 / 0.0.84 一模一样，工具面没变

### 这版我们几乎没改代码

把 0.0.84 和 0.0.85 的 npm 包逐文件 diff 了一遍：

```
cli.js        1,192 → 1,192   完全一致
index.js        747 →   747   完全一致
index.d.ts      901 →   901   完全一致
config.d.ts   9,317 → 10,005  只多了类型定义（tabGroup / background）
package.json  只变版本号和依赖
```

入口脚本一字没动，所以参数解析、stdio 握手、工具暴露全部和 0.0.84 一样。真正的代码改动全在 `playwright-core` 内部，通过 npm 依赖自动带上。

**所以这版的核心工作不是改代码，而是把兼容性验够。**

### 升级时注意
- 转发器里的 `MCP_VER` 默认值同步成 0.0.85 了。如果只升 npm 包不改转发器，启动时版本校验会发现对不上，然后自动把包装回 0.0.84，看起来就像「升级没生效」——跟 1.0.9 那次一样，是自愈逻辑在干活
- 全局目录里的旧版不影响使用，转发器优先用插件目录里的那份
- **新增的 `tabGroup` / `background` 两个配置项是浏览器扩展专属，手机上不用管**
- **`mcp.config.json` 里如果有相对路径，注意新版改成按配置文件目录解析了**。我们这个配置里全是绝对路径或环境变量，不受影响

### 🔒 外部审查又挖出七处（GPT 深度审查）

发版前请另一双眼睛把包翻了一遍，找到七个问题。全部核实为真，全部已修：

**P1 · GitHub Actions 脚本注入**（`.github/workflows/issue-notify.yml`）

以前是把 `${{ github.event.issue.title }}` 这类表达式直接拼进 `run:` 的 shell 脚本里。Issue 标题和正文是外部用户可控制的，GitHub 会先把表达式替换成实际内容再执行生成的脚本——攻击者用一个精心构造的标题就能让 Runner 执行任意命令，而这个 Job 后面还要用 SMTP 凭证发信。

改成：所有事件字段先进 step 级 `env:`，脚本里只读普通 shell 变量；标题先压成单行；多行正文用 `od` 现生成的随机 delimiter，防止正文里恰好出现 `EOF` 提前闭合。

**P2 · 升级不是事务性的**（`install.sh`）

原来是 `rm -rf 旧目录 && cp -r 新目录`。复制中途要是碰上磁盘满、权限错误或中断，旧目录已经没了、新目录只拷了一半、主配置却已经更新——一次失败的升级能把原本能用的安装毁掉。

改成先复制到同级 staging → 校验关键文件存在 → 旧目录改名为备份 → `mv` 原子上位 → 失败自动回滚。`--keep-deps` 的逐文件覆盖也改成 `cp` 到临时文件再 `mv`。

**P2 · 主配置根节点是数组时会假报成功**（`install.sh`）

只校验了 `main.mcpServers` 和 `main.pluginMetadata` 是不是对象，没管 `main` 自己。JavaScript 的数组可以挂命名属性，但 `JSON.stringify()` 不会序列化它们——结果是脚本打印「✅ 已合并进 …」，文件里却什么都没写。

改成入库前先 `isPlainObj(main)`，不是对象直接中止并提示从备份恢复，不静默重置（静默重置会毁掉用户其他配置）。

**P2 · 坏 build 拦截能被符号链接绕过**（`scripts/playwrightmcp.py`）

`_chrome_build()` 只看传入的路径字符串。做个 `chromium-1237/... -> chromium-1300/...` 的符号链接，实际指向 1300 的浏览器就会被当成 1237，直接绕过 1246+ 的拒绝逻辑。

改成先 `os.path.realpath()` 再提 build。

**P2 · README 解压目录名还是旧版**

`unzip …-v1.1.0.zip` 下面写的是 `cd …-v1.0.9`，照着敲会进不存在的目录。`check_consistency.py` 当时只查 `.zip` 文件名，没查目录名，所以 CI 没拦住。

已修 README，并给 `check_consistency.py` 补了「README 里所有 `playwright-mcp-for-operit-vX.Y.Z` 引用」的检查。

**P3 · 两处日期描述不准**

`docs/TROUBLESHOOTING.md` 把 `1.66.0-alpha-*` 的兼容实测标成 2026-09-19——那个版本 11-09 才存在。已拆成两条：旧驱动（09-19）与新驱动（11-14）分开写，各带实测数据。
`market/README.md` 的示例 `updatedAt` 还是 2026-09-30，同步到 2026-11-14。

**P3 · 浏览器探测细节**

- 扫描缓存目录时没检查可执行位，选了也起不来 → 加 `os.access(full, os.X_OK)`
- `PLAYWRIGHT_BROWSERS_PATH` 只能排第三，被硬编码的 `/root/.cache` 抢先 → 改成显式设置时独占优先（这也符合 Playwright 官方语义，顺带让测试可控）

**测试也补了三个**：符号链接指向坏 build、无执行位的 chrome 被跳过、坏 build 阈值能识别。现在单测 7/7。

### 🔒 第三轮审查：事务边界还不算完整

上一轮加的事务性部署方向对，但边界不够严。又被指出四处：

**P2 · `--keep-deps` 失败仍可能假报成功**

逐文件覆盖时，如果某个文件（比如 `playwrightmcp.py`）复制失败，原实现只 warn 一句就继续，并且 `KEEP_DEPS_EFFECTIVE=1` 已经置上——后面会跳过依赖安装。最终结果是：配置里声明 0.0.85、运行目录里还是 0.0.84、安装器照样打印部署完成。

改成两阶段：先把三个文件全部写到临时名，全部成功后再逐个原子改名；任一失败就清理临时文件并中止，不进入「成功」路径。

**P2 · 主配置提交是跑在运行目录部署之前的**

脚本结构上，主配置在 [5/6] 段开头就写入了，`deploy_run_dir()` 是后面才执行的。所以一旦部署失败，运行目录还是旧的，但主配置和插件元数据已经被改掉了——这不算回滚。

改成先把运行目录部署完（含结构校验），成功后才提交主配置。

**P2 · 两个 `mv` 之间存在窗口，且回滚失败也报「已回滚」**

`mv "$_dst" "$_backup"` 和 `mv "$_staging" "$_dst"` 各自是原子的，但中间有一段正式目录不存在的窗口。进程恰好在这里被 Ctrl+C / SIGTERM 杀掉，旧目录会卡在 `.bak` 里。

另外第二次 mv 失败时，原来的 `[ -d "$_backup" ] && mv ...` 没有检查恢复是否真的成功，却无条件打印「已回滚到旧安装」。

改了两处：

- 注册中断恢复：登记备份路径，在 EXIT / INT / TERM 时检查「备份在、正式目录不在」并把备份还原回去
- 回滚结果分三种报告：回滚成功 / 回滚也失败（给出备份路径和手动恢复命令）/ 无备份可回滚

**P3 · `PLAYWRIGHT_BROWSERS_PATH` 的代码比文档宽松**

这版文档写「显式设置时独占优先」，但代码是 `if env_path and os.path.isdir(env_path)` ——目录不存在就静默回退到默认路径。说的和做的不一致。

改成：只要设了变量就只认那个目录，目录不存在时打 WARN 但仍不回退。诊断结果才可预测。

**测试也跟着补了**

新增 `tests/test_deploy_rundir.sh`，用**确定性故障**（源目录不存在 / 源目录缺关键文件）验证失败路径，共 9 个断言。

特意不用 `chmod 000` 那种权限模拟：root 下 chmod 000 并不一定能阻止读取，测试会「声称失败、实际 cp 成功」，变成假绿。

### 🔒 第四轮：两个 P2 收尾（对方用故障注入复现出来的）

上一轮改的两处「方向对但没闭环」，这次补完：

**P2 · `--keep-deps` 的提交阶段没有回滚**

上一轮把「边复制边覆盖」改成了「先写临时名、再逐个 `mv`」，但 `mv` 阶段仍没有回滚。对方在隔离目录里让第二个 `mv` 确定失败，实际结果是：

```yaml
playwrightmcp.py  → 已更新为新版
requirements.txt → 仍是旧版
package.json     → 仍是旧版
临时文件          → 留下两个
```

也就是说不再「假报成功」了（进程以非 0 退出），但失败的升级仍会让运行目录处于**新旧文件混合**状态。

改成三阶段：

```yaml
① 三个新文件全部写临时名（此时正式文件未动）
② 现有正式文件备份成 .old（此时正式文件仍未动）
③ 逐个 mv 上位；任一失败就用 .old 回滚已替换项，再清理全部临时/备份文件
```

并且把这段逻辑抽成独立函数 `commit_keepdeps_files()`，这样能被单独 source 测试。

**P2 · 主配置校验发生得太晚**

上一轮加了根节点类型校验，但它在「运行目录部署之后」才执行。对方用临时 Operit 目录 + 合法的 `[]` 当主配置，跑了真实安装流程（`PW_MCP_INSTALL_MODE=skip`），结果：

```yaml
安装以 1 退出
主配置仍是 []              ← 保住了
但 Android 源目录已写入新版
但 Linux 运行目录已部署新版
但主配置旁还新增了一份 .bak
最后提示却是「已中止，未修改任何文件」   ← 与事实不符
```

改了两处：

- 主配置的 JSON 解析 + 根节点类型检查**提前到 [1.5/6]**，任何写入动作之前；`MAIN_CFG` 变量定义也跟着提到变量区
- 提交阶段的报错文案从「未修改任何文件」改为「主配置未被修改（插件目录可能已更新）」

改完实测同一场景：

```yaml
❌ 主配置根节点必须是 JSON 对象（实际: array）
   已中止，本次未修改任何文件。
--- 现场 ---
主配置内容: []          ← 原样
Android 目录: 不存在     ← 没创建
Linux 目录: 不存在       ← 没创建
```

这时「未修改任何文件」才是真的。

**新增测试 `tests/test_keepdeps_rollback.sh`（12 断言）**

同样只使用确定性故障：在 `PATH` 前置一个「第 2 次调用就失败」的假 `mv`。

```yaml
用例1 正常提交   → exit 0、三个文件都更新、无 .tmp / .old 残留
用例2 第二个 mv 失败 → 非 0 退出、三个文件全部回滚为旧版、无残留
```

### 🔒 第五轮：发布前的五处收尾

这轮的问题分两类——一类是真的坑，一类是「说和做不一致」。

**P2 · 卸载脚本拼错参数会真的执行卸载** ⚠️

`uninstall.sh` 第 38 行原来是：

```bash
*) warn "未知参数: $arg（已忽略）" ;;
```

对方实测 `bash uninstall.sh --dry-rnu`（`dry-run` 拼错一个字母）：

```yaml
退出码 0
主配置里的 playwrightmcp 条目被删除
Linux 运行目录被删除
最后还打印「卸载完成」
```

**用户只是手滑打错一个字，东西就没了。** 已改成直接 `warn` + 打印用法 + `exit 2`，与 `install.sh` 的未知参数处理保持一致。

**P2 · Node 版本承诺与上游不符**

我们的 `package.json` / `install.sh` / 转发器 / README 一直写 `>=18`，但上游有个容易漏的差异：

```yaml
@playwright/mcp@0.0.85   engines.node = ">=18"
playwright@1.66.0-alpha   engines.node = ">=20"   ←
playwright-core@1.66.0-alpha engines.node = ">=20" ←
```

也就是说这个插件实际跑在一个**上游没承诺支持**的环境上。npm 对 engines 不匹配只给 warning 不阻断，所以 Node 18 也许能跑，但没人保证。

这版统一提到 **`>= 20`**，四处一起改：`package.json`、`install.sh`（含检查逻辑与报错文案，并说明原因）、`scripts/playwrightmcp.py`（候选过滤 + die 文案）、`README` / `DEPLOY`。

> 这是本版唯一一处**可能影响现有用户**的变更：还在 Node 18 的环境会被告知需升级。

**P3 · 安装器的 Chromium 探测没有跟上转发器的修正**

上一轮把 Python 转发器的 `PLAYWRIGHT_BROWSERS_PATH` 改成了「显式设置就独占」，但 `install.sh` 第 343 行还是老三样：

```bash
for base in "$HOME/.cache/ms-playwright" "/root/.cache/ms-playwright" "${PLAYWRIGHT_BROWSERS_PATH:-}"; do
```

对方做了实际复现：默认缓存放 `chromium-1300`、指定目录放 `chromium-1237`，结果**安装器报 1300，转发器实际用 1237**。运行时选得对，但安装器打印的 build 信息和 ldd 检查结果都会误导用户。

已改成同一套逻辑：设了变量就只扫指定目录，否则扫两个默认位置。

**P3 · 两个 shell 回归测试没进 GitHub Actions**

`tests/test_deploy_rundir.sh`（9 断言）和 `tests/test_keepdeps_rollback.sh`（12 断言）本地都能跑，但 `checks.yml` 里没有调用它们——CI 一直是绿的，却从没覆盖这些失败路径。

已在 `checks.yml` 增加三个 step：

```yaml
- 部署失败路径回归（deploy_run_dir）
- keep-deps 回滚回归（commit_keepdeps_files）
- 卸载脚本未知参数应拒绝（期望 exit 2）
```

顺带说明：`test_deploy_rundir.sh` 目前只覆盖「源目录不存在 / 源目录缺关键文件 / 正常替换」三种；`mv` 中途失败、`INT/TERM` 中断恢复、staging 残留这些在 `test_keepdeps_rollback.sh` 与代码里的 trap 逻辑中覆盖。

**P3 · ZIP 里脚本没有执行位**

包内 `install.sh` / `uninstall.sh` 是 `600`，但 `CHANGELOG` 里写的是 `./install.sh`——照抄会得到 `Permission denied`（README 写的是 `bash install.sh`，所以正常用户不受影响）。

现在打包时统一 `chmod 755`，zip 内权限也确实是 755（已用 `zipfile.getinfo().external_attr` 验过）。

**这轮实测**

```yaml
install.sh --dry-run      exit 0
install.sh --bad-arg      exit 2
uninstall.sh --dry-rnu    exit 2   ← 以前是 0 并且真删
uninstall.sh --dry-run    exit 0   ← 正常路径不受影响
Chromium 探测             显式指定目录时选中该目录的 1237（不再是默认缓存的 1300）
zip 内 install.sh         755
```

### 🔒 第六轮：最后一道防线的补丁

对方又做了一次故障注入，这次打中的是「回滚本身失败」的情况。

**P2 · 回滚失败时会把唯一的备份删掉** ⚠️

上一轮的 `commit_keepdeps_files()` 在提交失败时会回滚，但代码是：

```bash
mv "$_dst/$_g.old.$$" "$_dst/$_g" || true     # 恢复失败被吞掉
...
rm -f "$_dst/$_f.old.$$"                        # 然后备份被删
```

三次 mv 故障注入后的实际结果：

```yaml
第一次 mv 成功 → 新版 playwrightmcp.py 上位
第二次 mv 失败 → 触发回滚
第三次 mv 失败 → 回滚也失败

现场：playwrightmcp.py 仍是新版，printing「已回滚」
      而 .old 备份已经被删——最后的恢复凭据没了
```

改成：逐个恢复、逐个检查结果。**只有全部恢复成功才清 `.old`**；任一失败就保留全部备份，并明确输出失败清单与备份目录。

**P3 · 安装器的 Chromium 探测还没跟转发器完全对齐**

上一轮改成了「显式设置 `PLAYWRIGHT_BROWSERS_PATH` 就独占」，但两边挑选 build 的策略仍不同：

```yaml
install.sh   → 选最大 build（1300）
Python 转发器 → 优先 PW_MCP_PREFERRED_BUILD（1237）
```

实测两个目录（1237 / 1300）时，安装器报 1300、实际用 1237。已让安装器也遵守 `PW_MCP_PREFERRED_BUILD`，未命中才退回「选最大」。

改完实测：

```yaml
安装器 dry-run → 选中 chromium-1237
Python 转发器  → 选中 chromium-1237
```

**P3 · 文档与代码描述不一致**

`PLAYWRIGHT_BROWSERS_PATH` 在三个地方仍被描述为「额外的浏览器搜索目录」：

```yaml
scripts/playwrightmcp.py  docstring
docs/DEPLOY.md            探测顺序表
docs/DEPLOY.md            环境变量表
```

统一改成「显式设置后只搜索该目录，目录不存在时告警但不回退」。

**P3 · 验证指南有四处过期内容**

文件清单写 27 个（实际 29）、一键验证列表漏了 `test_keepdeps_rollback.sh`、文件清单没列新测试、Node 说明容易被读成「只有 dry-run 需要 Node 20」。均已修正。

**测试新增用例3（17 断言）**

```yaml
用例1 正常提交            → exit 0，三文件更新，无残留
用例2 第二个 mv 失败      → 回滚成功，三文件全恢复，无残留
用例3 第二个+第三个都失败  → 回滚未完成提示，.old 备份全保留（3 个），.tmp 已清
```

### 🔒 第七轮：失败路径最后一点状态一致性

这轮没有 P1/P2 了，三个都是 P3——都是「失败之后状态没收干净」的细节。

**P3 · `--keep-deps` 没覆盖「升级前不存在的文件」**

备份阶段只备份已存在的文件：

```bash
if [ -f "$_dst/$_f" ]; then cp -p ...  fi
```

但回滚时对每个已提交的文件都去找 `.old`，于是：

```yaml
升级前：playwrightmcp.py 旧 / requirements.txt 不存在 / package.json 旧
结果：替换到 package.json 时失败

回滚后：playwrightmcp.py 恢复成功
       package.json 保持旧版
       新创建的 requirements.txt 留在正式目录 ← 多余文件
       并报告「找不到 requirements.txt 的备份」
```

改成：备份阶段记录 `_absent`（升级前不存在的文件）；回滚时这类文件**直接删除新建的那份**，并检查删除是否成功。

**P3 · 安装器探测不认识 `PLAYWRIGHT_CHROME_BIN`**

Python 转发器的优先级是：

```yaml
PLAYWRIGHT_CHROME_BIN → PLAYWRIGHT_BROWSERS_PATH → 默认缓存
```

但 `install.sh` 的 `find_chrome()` 只扫缓存目录。用户用 `PLAYWRIGHT_CHROME_BIN=/tmp/custom-chrome` 指定浏览器时，安装器会报「未发现本机 Chromium，将自动下载」，而实际运行时用的正是用户指定的那个——诊断信息与实际行为对不上。

已在 `find_chrome()` 开头加上同样的优先级（含 >1MB 的大小校验，与转发器一致）。

**P3 · 把 1237 称作「钉死」不准确**

实际代码是：默认优先选 1237 → 1237 不存在时回退选最大 → 选中已知坏 build（>=1246 且 != 1237）时运行时拒绝启动。这是**默认优先级策略**，不是硬编码钉死。

README / 验证指南里的措辞已统一改成「默认优先选用」。

**测试新增用例4（17 → 24 断言）**

```yaml
用例4 升级前某文件不存在 + 替换失败
  → py 恢复旧版、新建的 req 被删除、pkg 保持旧版、无 .old/.tmp 残留、无「回滚未完成」误报
```

### 🔒 第八轮：符号链接与文档同步

R7 已是发布候选，这轮只剩两处细节：

**P3 · `PLAYWRIGHT_CHROME_BIN` 是符号链接时安装器识别失败**

```bash
stat -c%s "$PLAYWRIGHT_CHROME_BIN"   # 普通 stat 不跟随符号链接
```

指向真实 chrome 的符号链接，读出来的是链接本身那几十字节的长度，于是被判「不是浏览器」，安装器报「未发现本机 Chromium」。

改成 `stat -L -c%s`（跟随链接），并且 build 号也改用 `realpath` 提取——否则 `chromium-1237/... -> chromium-1300/...` 会把 1300 误报成 1237。

实测：

```yaml
PLAYWRIGHT_CHROME_BIN=/tmp/sym_test/chromium-1237/chrome-linux/chrome  (-> chromium-1300)
安装器 → ✅ 复用已有 Chromium：.../chromium-1237/chrome-linux/chrome（build=1300）
```

**P3 · 验证指南三处没同步**

```yaml
材料引用       v1.1.0_review_R2.txt → REVIEW_R7.txt
末尾 md5       b8caf8af… → 771d62cb…
一键验证列表   漏了 test_keepdeps_rollback.sh
```

### 📖 文档：TROUBLESHOOTING 新增问题 14

把一份真实的排障记录（来自另一台设备，无 root、只能看 App 日志）提炼成「问题 14：插件启用了但 MCP 不响应 / 握手超时」：

- **先看 UI**：Operit 1.12.2+2（versionCode 53）起，启动失败时 UI 会直接给出真实原因（stderr / 缺环境变量 / 入口路径错误 / 进程崩溃），先看它就够，不必一上来就查进程
- **三查法**：进程 / App 日志 / `bootstrap.log`，按这个顺序（旧版必走，新版通常用不到）
- **硬判据**：进程表里出现第三条（`cli.js --headless ... --executable-path`）才算握手成功，只有桥进程不算
- **因果陷阱**：「文件是新的 ≠ 桥被拉起来了」——桥文件被释放和 App 去调用它是两件事，`/root/bridge` 不存在往往只是「App 没调桥」的结果，不是原因
- **启动链图示**：`Operit → spawn-helper.js → venv/bin/python -m playwrightmcp`
- **判别表**：四种进程组合分别对应什么结论、下一步做什么
- 附带两个常见误判：有 UI 权限 ≠ 无障碍服务在跑；只换文件不重启 App 桥不会重载

### 升级方法
解压后运行 `./install.sh`，装过的会自动升级。手动也行：`npm i -g @playwright/mcp@0.0.85`

---

## [1.0.9] - 2026-11-01

### 跟上上游 0.0.84

`@playwright/mcp` 从 0.0.83 升到 0.0.84，`playwright-core` 跟着从 `1.64.0-alpha-1790635538000` 走到 `1.65.0-alpha-2026-10-30`。

这次上游动的东西不算多，但对实际用起来挺有帮助：

- `browser_tabs` 加了 `isolatedContext`。传个名字进去就开一个独立的浏览器上下文，cookie 和 localStorage 都是分开的。以前想同时挂两个账号，得反复退登录清缓存，现在开两个 context 就互不干扰
- `browser_find` 加了 `maxResults`。之前页面上有几十个匹配项会全吐出来，现在能限个数，只找一个元素的时候省不少 token
- `browser_network_requests` 加了 `all`。以前页面一跳转，之前的请求记录就没了；现在打开这个开关能拿到整段会话的请求，排查接口问题方便些
- 新增启动参数 `--redact-url-params=access_token,code`，URL 里的敏感参数会被打码，免得 token 混进日志。这只是图个方便，别当成安全边界——真不该露的东西，本来就不该出现在 URL 里
- `target` 的写法也放宽了，JS、Python、Java、C# 四种风格的定位器都能认
- 新增 `--ignore-roots`：客户端声明了 workspace roots 但没法响应 `roots/list` 时，可以忽略这项检查

### Chromium 还是用 1237

上游 0.0.84 配套的 Chromium 是 1252（Chrome 157.0.8103.15），比 0.0.83 那会儿的 1247 又往前跳了 5 个。

但之前踩过坑：proot 环境里 rev1246 以上的 build 一启动就是 SIGTRAP（exit 133），根本起不来。所以 1237 继续留着用。

这次特意试了跨版本能不能跑——playwright 1.65 跟 Chromium 1237 差了 15 个 build，实测启动、渲染、截图、执行 JS 都正常，没报错。`PW_MCP_KNOWN_BAD_MIN=1246` 的拦截逻辑原样保留，自动下载万一跑到新 build 上还能拦住。

### 在 W200DS 上试了一遍

- `npm install @playwright/mcp@0.0.84` 只更新了三个包（mcp、playwright、playwright-core），4 秒左右完成，Chromium 不用重下
- 版本核对：mcp 0.0.84 / playwright 1.65.0-alpha-2026-10-30 / playwright-core 1.65.0-alpha-2026-10-30
- Chromium 冷启动 0.6 秒，机器忙的时候大概 3 秒，报出来的浏览器版本是 152.0.7977.8
- 打开页面、截图、取 DOM 内容、跑 JS 都正常，跟升级前没区别
- 新参数试了两个：`browser_find(maxResults=1)` 只回一条，输出里写着 showing first 1；`browser_tabs(isolatedContext="test-ctx")` 建出来的 tab 会标注 `[isolatedContext: test-ctx]`
- 工具数量还是 25 个，跟 0.0.83 一样

### 升级时注意

- 转发器里的 `MCP_VER` 默认值同步成 0.0.84 了。如果只升 npm 包不改转发器，启动时版本校验会发现对不上，然后自动把包装回 0.0.83，看起来就像“升级没生效”，其实是自愈逻辑在干活
- 全局目录里留着的旧版（比如 `/usr/lib/node_modules` 下的 0.0.80）不影响使用，转发器优先用插件目录里的那份

### 顺手把安装脚本的几处毛病理了理

这版除了跟上游，`install.sh` 里几个长期存在的问题也一起处理了。跟 0.0.84 没关系，是之前就有的：

- **结构校验失败却报成功**：以前只打一句「存在校验项失败」就继续往下走，最后照样打印「✅ 部署完成」。现在会直接报错退出，退出码非 0，自动化调用能正确判断
- **`--keep-deps` 不查版本**：以前不管现有依赖是什么版本都原样保留。从 0.0.83 升上来还带这个参数的话，会留下旧包，转发器启动时的版本校验又要把包装回去，白绕一圈。现在先查实际版本，对不上就走常规安装并明确提示
- **备份名同秒覆盖**：主配置备份以前精确到秒，同一秒连跑两次会互相覆盖。现在文件名带上了进程号
- **主配置非原子写入**：以前直接覆盖原文件，中途被杀掉或断电可能留下半截 JSON。现在先写临时文件再重命名，不会出现半个文件
- **参数写错误装**：命令行参数打错时，以前只提示「未知参数，已忽略」然后照常安装。现在直接拒绝、打印用法并退出（码 2）
- **非法 `PW_MCP_INSTALL_MODE`**：以前会被静默当成 `local`，现在明确报错
- **小加固两处**：Chromium 探测加上了可执行权限过滤；npm 安装前会先检查运行目录是否可写

### 插件 ID 统一成 playwrightmcp

这是个历史遗留问题：仓库里部署脚本用的 ID 是 `playwright_mcp`（带下划线），但 Operit 市场装出来和实机运行的目录都是 `playwrightmcp`（不带下划线）。

结果就是：手动跑 `install.sh` 会装出另一个 ID 的插件，跟市场版并存出现在列表里，用户不知道该用哪个；而且会把新版文件放到没人读取的目录，看起来像「升级了没生效」。

这版统一改成 `playwrightmcp`，转发器文件也跟着从 `scripts/playwright_mcp.py` 改名为 `scripts/playwrightmcp.py`，仓库里 14 个文件共 124 处引用一起对齐。

装过旧 ID 的人升级时，安装脚本会把 `mcpServers` 和 `pluginMetadata` 里的旧条目一并清掉，不会出现新旧两个条目同时被加载；卸载脚本也会两个 ID 都清。旧运行目录（`~/mcp_plugins/playwright_mcp`）不自动删，装的时候提示一句，确认没用了自己删就行。这条迁移路径也补了回归测试。


## [1.0.8] - 2026-09-30
### ⬆️ 上游同步
- 适配 `@playwright/mcp` **0.0.82 → 0.0.83**（上游 8 项 bugfix：`browser_find` 正则/文件名支持、navigate/reload 遇对话框报错、下载中关闭浏览器防崩、`wait_for` 超时明示、WebMCP 陈旧标签绑定、snapshot 正则名加引号等）
- `playwright-core` 同步 `1.64.0-alpha-1790635538000`
### 🔒 兼容性（决策保持不变）
- 新增 `PW_MCP_KNOWN_BAD_MIN`（默认 1246）：最终选中的 Chromium build >= 此值（且 != 1237）时**拒绝启动**（防 proot SIGTRAP；自动下载路径同样拦截；`PW_MCP_PREFERRED_BUILD=0` 时依旧生效）
- **Chromium build 偏好继续钉 1237**：上游 0.0.83 官方配套为 1247，但 proot 下 rev1246+ 启动即 SIGTRAP；1237 在旧/新驱动下均实测兼容，跨 build 复用策略不变（`PW_MCP_MIN_BUILD` / `PW_MCP_PREFERRED_BUILD` 保持 1237）
### ✅ 本机验证
- 全链路实测：npm 升级 → 重启 MCP → 25 工具在线 → navigate / snapshot / screenshot / wait_for / close 全通过

## [1.0.7] - 2026-09-23

### 🐛 修复（来自社区反馈）
- **「自动下载 Chromium」必然失败**：`install chromium` → **`install-browser chromium`**。
  `@playwright/mcp@0.0.82` 的 cli.js 只把 `install-browser` 映射给下游 Playwright，
  直接传 `install chromium` 会被顶层解析器拒掉（`too many arguments: install, chromium`）。
  受影响共 5 处：转发器下载调用、docstring、两处提示文本、DEPLOY 表格。
  ※ 本机已有 Chromium 的环境永远不会走到这条路径，属长期潜伏 bug —— 感谢 @bingfengcxl-crypto 报告（#4）

### 🛡️ 兼容性
- 新增排障条目 [问题 13](docs/TROUBLESHOOTING.md)：**proot 下新版 Chromium（rev1246+）启动即 SIGTRAP**
  （exit 133 / GPU process exit_code=5），并给出 chromium-1237 的回退与下载命令 —— 感谢 @bingfengcxl-crypto 报告（#5）
- 转发器新增 **`PW_MCP_PREFERRED_BUILD`**（默认 `1237`）：本机存在多个 build 时优先选已知可用版本，
  不再「选最新」（新版在 proot 下会崩）
- `PW_MCP_MIN_BUILD` 默认值 **1243 → 1237**（原值会让 1237 白刷一条 WARN；`install.sh` 同步）

### 📄 文档
- DEPLOY：Chromium 行补 `install-browser` 与 build 偏好说明；环境变量表补 `PW_MCP_PREFERRED_BUILD`

## [1.0.6] - 2026-09-19

### ⬆️ 上游跟进
- `@playwright/mcp` **0.0.80 → 0.0.82**
- 工具数订正：**24 → 25**（v1.0.0 ~ v1.0.5 文档漏列了 `browser_emulate_media`，实测 `tools/list` 一直是 25）
- 上游新特性：60fps 可样式化视频录制（`browser_start_video`，devtools opt-in）、WebMCP 工具、`--profile-dir-name`

### 🔧 install.sh
- `--keep-deps` 真正生效（此前会先 `rm -rf` 整个运行目录再谈"保留依赖"）
- 默认改用 **npm 官方源**（0.0.82 依赖 `playwright-core@1.64.0-alpha-*`，国内镜像未同步会报 `ETARGET`）
- 转发器下载：`.tmp` → 校验 → 原子替换（不再可能留半成品）
- 配置合并加类型校验（`mcpServers` / `pluginMetadata` 非对象时重置并告警，不静默）
- 主配置备份失败时明确中止；备份上限 5 份
- `uninstall.sh` 去掉 `eval`（消除字符串逃逸面）
- **patch 1**：`pluginMetadata.version` 改用**插件自身版本**（此前误用上游 MCP 版本 `0.0.82`）
- **patch 3**：`KEEP_DEPS_EFFECTIVE` 提升到全局初始化区 —— 修掉 `--dry-run` 下 `set -u` 的 `unbound variable` 崩溃
- **patch 3**：备份清理改用便携写法 `ls -1t`（原 `find -printf` 属 GNU 扩展，Termux 的 toybox `find` 不支持）
- **patch 3**：python3 缺失时，转发器下载校验自动降级为「shebang + 体积下限」，不再 100% 失败
- **patch 3**：`--keep-deps` 的文件复制循环由 `[ -f ] && cp` 改为 `if`，消除 `set -e` 返回值传染

### 🐍 转发器（scripts/playwright_mcp.py）
- 新增 node 版本校验（< 18 或解析失败则跳过该候选，日志可见）
- `bootstrap.log` 日志轮转（超 1MB 转 `.log.1`；`PW_MCP_LOG_MAX` 可调）
- **patch 3**：新增 `_int_env()` —— 非法整型环境变量（如 `PW_MCP_LOG_MAX=1m`）只告警并回退默认值，**不再 ValueError 崩溃**
- **patch 3**：`run()` 增加 `cwd` 参数；本地 `npm install` 显式传 `cwd=HERE`（不再隐式依赖进程 cwd）

### 📌 版本语义变更（升级必读）
- 自 **1.0.6** 起，`pluginMetadata.version` 表示**插件自身版本**（`1.0.6`），与上游 `@playwright/mcp` 版本（`0.0.82`）**解耦**
- 从旧版升级后，Operit 插件页显示的版本会由 `0.0.x` 变为 `1.0.6` —— **这是预期行为**，仅元数据变化，功能不受影响

### ✅ 验证记录
- **三轮代码审查**（作者自审 → 陌生视角 → 外部 AI → 作者终审），累计修复 **28 项**
- 实测覆盖：隔离安装 / 重复安装（幂等）/ `--dry-run` / `--dry-run --keep-deps` / `--keep-deps` / `uninstall` / 非法环境变量容错 / 备份上限清理
- 端到端：MCP 握手成功，`tools/list` 返回 **25** 个工具；Chromium 复用 `chromium-1237`（跨驱动兼容，无需重下）

## [1.0.5] 及更早
历史版本见 [Releases](https://github.com/x15907982411/playwright-mcp-for-operit/releases)。
