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
- `summary`
- `findings`

JSON 缺失、重复、不可解析或字段不完整时，按诊断不可用处理，不从终端文案猜结论。

### 2. 只输出一个结论

按 `conclusion` 映射为 PM 语言：

| conclusion | PM 结论 | 下一步 |
|---|---|---|
| `healthy` | 框架和当前消费仓正常 | 无需操作；可补充不阻断的环境提醒 |
| `upgrade_available` | 框架有新版本 | 建议转 `/pmai-upgrade`；未确认前不升级 |
| `consumer_sync_required` | 全局框架可用，但当前消费仓的框架入口或旧结构需要同步 | 说明是 hooks、OpenCode、Git hook、忽略规则还是旧版副本；未确认前不写仓库 |
| `consumer_invalid` | 当前消费仓缺少必需文件、归位错误，或活动工作无法安全恢复 | 按影响列出最小整理清单；不得自动移动文件或修改状态 |
| `broken` | PMAI 安装或宿主入口损坏 | 给出最小修复动作；未确认前不运行 repair / reinstall |

远程不可达时只能说“暂时无法确认是否为最新版”，不能报告“已经最新”。可选浏览器适配器缺失只作为提醒，不把非 Web 工作误报为框架损坏。

消费仓检查按当前阶段判断，不把初始化仓、设计中和构建中的项目套成同一张静态清单：

- 根目录产品文档、`docs/` 分类目录和索引是否存在、归位且可随 Git 携带；
- 模块 `discussion.md / decisions.md / spec.md` 与 `.work-meta.json` 是否符合当前 lifecycle；
- `.pm-workflow/project.yml` 是否可解析，定稿来源、实现根和 entrypoints 是否存在且位于仓内；`definition.source_hash` 是当时的决定证据，不因规格后来变化而误报漂移；
- 探索稿固定检查 `mockups/manifest.json`、资源和生成看板；正式 prototype / product 位置只认 `project.yml:implementation`，不写死 `prototype/`；
- active build 的 worktree、branch 和验收目录是否仍可恢复；
- 旧 requirements / task / 项目级 PMAI 副本、错误忽略规则、symlink、路径穿越和被 Git 跟踪的敏感配置是否需要处理。

不得把消费仓与模板逐字比较。`PRODUCT.md`、`AGENTS.md`、`CLAUDE.md` 等允许项目持续补充，只检查必需结构、入口锚点和可解析性。

### 3. 修复必须二次确认

只有 PM 明确确认对应动作后才能执行：

- 全局框架有新版本：完整转入 `/pmai-upgrade`，按其升级模式确认门执行。
- 全局宿主入口损坏：运行 `"$PMAI_HOME/bin/pmai" doctor --repair --json`，完成后再跑一次 `--check --json` 复验。
- 当前消费仓项目 hooks 漂移：在诊断返回的 `consumer.root` 内运行 `bash "$PMAI_HOME/scripts/install-project-hooks.sh"`，然后再跑只读 doctor 复验。
- 当前消费仓 OpenCode 入口漂移：运行 `bash "$PMAI_HOME/scripts/install-opencode-commands.sh" --project "<consumer.root>"`，然后复验。
- 当前消费仓 Git hook 漂移：在消费仓根运行 `bash "$PMAI_HOME/scripts/install-hooks.sh"`，然后复验。
- 当前消费仓残留旧版项目副本：先列出识别依据；PM 明确确认清理后才运行 `"$PMAI_HOME/bin/pmai" uninstall --local "<consumer.root>"`，然后复验。
- 当前消费仓文件缺失、文档错位、原型游离或状态损坏：只按严重程度列出 repo-relative 差异与建议归位；移动、补写、删除或改状态前等待 PM 确认。`doctor --repair` 不处理这些项目内容。
- 安装不存在或损坏到无法 repair：说明需要重新安装；卸载、删除或覆盖前继续遵守相应确认门。

一次只执行诊断建议的最高优先级动作。修复后若出现新的独立问题，重新报告并等待，不连续猜测执行。

## 输出合同

```text
当前结论：<正常 / 框架待升级 / 当前消费仓待同步 / 当前项目需要整理 / 安装损坏>

框架：<版本、是否为远程 main、安装是否完整>
当前项目：<所处阶段、文档与原型/实现位置是否正常；不适用时省略>
宿主入口：<只汇总异常；全部正常时一句话>

建议下一步：<唯一动作；无需操作时明确写无需操作>
```

不要向 PM 展开 symlink 数量、内部锁、JSON schema、CLI source / audit target 等实现细节；除非某项异常需要这些证据定位。

## Rules

- 默认只读。不得把 `pmai doctor --repair` 当检查命令。
- 不调用 `/pmai-status` 或 `status-view.py` 诊断框架；它们属于产品进度。
- 不把兼容命令 `pmai status` 当正式入口；底层统一使用 `pmai doctor --check`。
- 不自动运行升级、项目 hooks 刷新、文件迁移、legacy 清理、卸载或重装。
- 不执行 `project.yml` 中声明的 install / build / test / typecheck / start 命令。
- 不读取或回显 `.claude/lark-publish.json` 等敏感配置内容；只检查是否被 Git 跟踪或是否为危险 symlink。
- 只执行已安装目标自己的 doctor，不用其它版本的脚本解释或修复目标安装。
- 诊断结果与实际退出码矛盾时失败关闭，不报告假健康。
