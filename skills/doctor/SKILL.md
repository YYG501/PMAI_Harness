---
name: pmai-doctor
description: |
  只读检查 PMAI 框架、宿主入口，以及当前消费仓的文件结构、文档归位、原型与构建状态是否健康。
  触发词：检查 PMAI / 框架健康 / 消费仓需要升级吗 / doctor / PMAI 是否正常。
triggers:
  - 检查 PMAI
  - 框架健康
  - 消费仓需要升级吗
  - pmai doctor
  - PMAI 是否正常
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# /pmai-doctor

> PMAI 框架与消费仓诊断入口。默认只读；修复、升级、文件迁移和消费仓刷新都必须另行得到 PM 确认。

## 定位

- `/pmai-status` 只回答产品进度、当前模块和下一步。
- `/pmai-doctor` 只回答框架是否健康、是否有新版本，以及当前消费仓的入口、文件结构和工作状态是否符合已安装版本。
- `/pmai-upgrade` 只执行已经确认的全局框架升级。

本 skill 可以在消费仓、普通 Git 仓或未初始化目录运行，不执行项目 preamble，不要求存在 `PRODUCT-STATE.md`。

## Workflow

### 1. 运行只读诊断

```bash
PMAI_HOME="${PMAI_HOME:-$HOME/.pmai}"
"$PMAI_HOME/bin/pmai" doctor --check --json
```

如果 `PMAI_HOME/bin/pmai` 不存在，只报告“PMAI 未安装或安装不完整”，给出安装入口；不要从其它 checkout 猜一个 doctor 代跑。

命令 stdout 必须是唯一 JSON 对象，且至少包含：

- `schema_version = 1`
- `conclusion`
- `recommended_action`
- `framework`
- `consumer`
- `checks`
- `product_progress`
- `pm_report`
- `summary`
- `findings`

JSON 缺失、重复、不可解析或字段不完整时，按诊断不可用处理，不从终端文案猜结论。

消费仓 finding 还必须读取 `kind` 与 `blocking`，不能只看 `level`：

- `framework_managed_sync`：框架入口、托管骨架或忽略规则待刷新；
- `legacy_compatible`：已明确声明的合法旧产出，不需要补造内容；
- `compatibility_declaration_required`：旧仓可有边界识别，但仍需 PM 确认兼容关系；
- `project_content_invalid`：真实内容、状态或恢复证据损坏；只有这类 blocking finding 才能进入 `consumer_invalid`。

### 2. 版本未知时申请联网复查

当 `framework.update_available = null` 且 `framework.remote_url` 非空时，不能直接结束版本判断。必须通过当前宿主的权限机制申请联网，在沙箱外执行同一条只读查询（最多等待 10 秒）：

```bash
git -C "$PMAI_HOME" ls-remote --heads origin refs/heads/main
```

- 查询成功且返回唯一 `refs/heads/main` 时，把远端 commit 与 `framework.head` 比较：相同就报告“已确认是最新版”，不同就把“PMAI 有新版本可以更新”加入需要解决。
- 宿主未授权联网、当前宿主没有权限申请能力、查询超时或查询仍失败时，才保留“暂时无法确认 PMAI 是否为最新版”。
- 查询 stderr 只用于判断这次复查失败，不向 PM 回显 remote URL、用户名、凭据路径或完整底层错误；不得修改 Git 配置、SSH 配置、凭据或网络设置。
- CLI 自身不越过宿主沙箱；联网授权和沙箱外重试由执行本 Skill 的当前宿主完成。

### 3. 一个结论，完整报告每项检查

先给一个 PM 能直接理解的结论：

| conclusion | PM 结论 |
|---|---|
| `healthy` | PMAI 正常；若检查项有提醒，则说“PMAI 可以正常使用，但当前项目有 N 项需要处理” |
| `upgrade_available` | PMAI 可以正常使用，但有新版本需要处理 |
| `consumer_sync_required` | PMAI 可以正常使用，但当前项目有 N 项需要处理 |
| `consumer_invalid` | 当前项目的 PMAI 工作流无法正常使用 |
| `broken` | PMAI 无法正常使用 |

随后按 JSON `checks` 的既定顺序逐项报告，正常项也不能省略：

1. PMAI 安装
2. AI 工具接入
3. 项目必需资料
4. 文档与历史资料
5. 原型和产品文件
6. 正在进行的工作
7. 项目安全

状态翻译固定为：`normal` = 正常，`attention` = 需处理，`problem` = 有问题，`not_applicable` = 不适用，`unknown` = 暂时无法确认。不得只列异常项。

“需要解决”只能逐项渲染 `pm_report.action_items`，不得重新扫描 `findings`、远程 warning、浏览器 warning 或合法旧模块后自行追加。`recommended_action` 只决定首先建议处理哪一项，不能让其它 action item 消失。不要向 PM 输出 `consumer_invalid`、`topology`、`blocking`、`hooks drift` 等内部名称。

“仅供参考”逐项渲染 `pm_report.notices`。远程版本未知、可选浏览器适配器提醒和 `legacy_compatible` 只能出现在这里，不能进入“需要解决”；第 2 步联网复查成功后，用已确认的版本结果替换对应版本提醒。

最后单列“项目进度提示”，读取 `pm_report.progress`。设计中、等待制作、制作中以及“尚未确定本次修改页面”等内容只放这里，不参与总结论，不进入“需要解决”。即使某个模块暂不能开始制作，只要 PMAI 安装、项目接入和项目结构正常，结论仍是 PMAI 正常。

远程不可达时只能说“暂时无法确认是否为最新版”，不能报告“已经最新”。可选浏览器适配器缺失只作为提醒，不把非 Web 工作误报为框架损坏。

消费仓检查按当前阶段判断，不把初始化仓、设计中和构建中的项目套成同一张静态清单：

- 根目录产品文档、`docs/` 分类目录和索引是否存在、归位且可随 Git 携带；
- 模块 `discussion.md / decisions.md / spec.md` 与 `.work-meta.json` 是否符合当前 lifecycle；
- `.pm-workflow/project.yml` 是否可解析，定稿来源、实现根和 entrypoints 是否存在且位于仓内；`definition.source_hash` 是当时的决定证据，不因规格后来变化而误报漂移；
- 探索稿固定检查 `mockups/manifest.json`、资源和生成看板；正式 prototype / product 位置只认 `project.yml:implementation`，不写死 `prototype/`；
- active build 的 worktree、branch 和验收目录是否仍可恢复；
- 旧 requirements / task / 项目级 PMAI 副本、错误忽略规则、symlink、路径穿越和被 Git 跟踪的敏感配置是否需要处理。

不得把消费仓与模板逐字比较。`PRODUCT.md`、`AGENTS.md`、`CLAUDE.md` 等允许项目持续补充，只检查必需结构、入口锚点和可解析性。

消费仓布局合同复用现有 `.pm-workflow/config.yml:consumer`，不新增平行 manifest：

- 当前标准文档入口始终是 `docs/INDEX.md`，模块入口始终是 `docs/modules/INDEX.md`；
- 旧项目的 `docs/索引.md` 等文件只有被标准入口明确链接时才视为有意保留，不能反过来替代标准入口；
- `consumer.layout_version` 标记布局版本，`consumer.paths.archive` 可声明旧项目沿用的归档目录；
- `consumer.compatibility` 只记录不能按当前三件套解释的 `legacy / retired / split` 模块；未声明模块默认 current；
- active `.work-meta.json` 始终优先并按 lifecycle 严格校验，兼容声明不能降级绕过；
- 未标版本旧仓可识别非空 `spec + decisions` 和合并式 spec，但只能返回待声明兼容，不能直接判内容损坏；
- `.gitkeep` 不是内容合同，目录已有内容时不得要求它存在；空白 `discussion.md / decisions.md / spec.md` 也不能让检查通过。

### 4. 修复必须二次确认

只有 PM 明确确认对应动作后才能执行：

- 全局框架有新版本：完整转入 `/pmai-upgrade`，按其升级模式确认门执行。
- 全局宿主入口损坏：运行 `"$PMAI_HOME/bin/pmai" doctor --repair --json`，完成后再跑一次 `--check --json` 复验。
- 当前消费仓项目 hooks 漂移：在诊断返回的 `consumer.root` 内运行 `bash "$PMAI_HOME/scripts/install-project-hooks.sh"`，然后再跑只读 doctor 复验。
- 当前消费仓 finding 提供 `repair_action.id = sync_consumer_entry`：先运行 `python3 "$PMAI_HOME/scripts/sync-consumer-entry.py" --repo-root "<consumer.root>" --check` 只读确认可同步；只有 PM 明确确认后才把 `--check` 改为 `--apply`。该动作只更新 `AGENTS.md` 的 PMAI Startup 托管区块；旧入口迁移时保留项目启动补充，遇到未知旧规则、损坏标记或 symlink 必须停止并请求人工确认。完成后重新运行 doctor 复验。
- 当前消费仓 OpenCode 入口漂移：运行 `bash "$PMAI_HOME/scripts/install-opencode-commands.sh" --project "<consumer.root>"`，然后复验。
- 当前消费仓 Git hook 漂移：在消费仓根运行 `bash "$PMAI_HOME/scripts/install-hooks.sh"`，然后复验。
- 当前消费仓残留旧版项目副本：先列出识别依据；PM 明确确认清理后才运行 `"$PMAI_HOME/bin/pmai" uninstall --local "<consumer.root>"`，然后复验。
- 当前消费仓需要兼容声明：先展示 doctor 的推断与歧义，逐项让 PM 确认；确认后只更新现有 `.pm-workflow/config.yml:consumer`，不得新建布局文件、移动业务文档或生成空白三件套，然后复验。
- 当前消费仓文件缺失、文档错位、原型游离或状态损坏：只按严重程度列出 repo-relative 差异与建议归位；移动、补写、删除或改状态前等待 PM 确认。`doctor --repair` 不处理这些项目内容。
- 安装不存在或损坏到无法 repair：说明需要重新安装；卸载、删除或覆盖前继续遵守相应确认门。

可以一次列出全部问题，但一次只执行 PM 已确认的一个修复动作。修复后重新检查并完整报告七项结果，不连续猜测执行。

## 输出合同

```text
结论：<一句话结论>

检查结果：
[正常 / 需处理 / 有问题 / 不适用 / 暂时无法确认] PMAI 安装
[正常 / 需处理 / 有问题 / 不适用 / 暂时无法确认] AI 工具接入
[正常 / 需处理 / 有问题 / 不适用 / 暂时无法确认] 项目必需资料
[正常 / 需处理 / 有问题 / 不适用 / 暂时无法确认] 文档与历史资料
[正常 / 需处理 / 有问题 / 不适用 / 暂时无法确认] 原型和产品文件
[正常 / 需处理 / 有问题 / 不适用 / 暂时无法确认] 正在进行的工作
[正常 / 需处理 / 有问题 / 不适用 / 暂时无法确认] 项目安全

需要解决：
<列出全部需要处理的问题；没有则写“无”>

仅供参考：
<列出版本暂未确认、可选浏览器能力和合法旧模块；没有则写“无”>

项目进度提示：
<只写当前工作进度和暂不能开始制作的原因；没有则写“无”>
```

不要向 PM 展开 symlink 数量、内部锁、JSON schema、CLI source / audit target 等实现细节；除非某项异常需要这些证据定位。

## Rules

- 默认只读。不得把 `pmai doctor --repair` 当检查命令。
- 不调用 `/pmai-status` 或 `status-view.py` 诊断框架；它们属于产品进度。
- CLI 不再提供 `pmai status`；底层统一使用 `pmai doctor --check`。
- 不自动运行升级、项目 hooks 刷新、文件迁移、legacy 清理、卸载或重装。
- 不执行 `project.yml` 中声明的 install / build / test / typecheck / start 命令。
- 不读取或回显 `.claude/lark-publish.json` 等敏感配置内容；只检查是否被 Git 跟踪或是否为危险 symlink。
- 只执行已安装目标自己的 doctor，不用其它版本的脚本解释或修复目标安装。
- 诊断结果与实际退出码矛盾时失败关闭，不报告假健康。
