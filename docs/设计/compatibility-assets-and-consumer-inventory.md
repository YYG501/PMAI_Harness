# PMAI 兼容资产与消费仓清单

> 状态：Living document
> 最近核对：2026-08-11
> 适用范围：PMAI 生成器仓的历史合同、迁移入口和已知消费仓
> 决策依据：旧消费仓可恢复、可升级，但不无限兼容

## 1. 这份清单解决什么

兼容代码不能只回答“旧数据还能不能读”，还要回答：

1. 哪个入口仍在读取旧格式。
2. 当前版本还会不会继续写这个格式。
3. 哪个真实消费仓仍然依赖它。
4. 旧工作如何恢复或升级。
5. 满足什么条件后可以删除兼容分支和对应测试。

本文件只登记事实和退出条件，不授权迁移消费仓，也不授权删除兼容代码。消费仓迁移必须在 PM 确认、工作区可控且 active work 已有明确处理方案后单独执行。

## 2. 支持等级

| 等级 | 含义 | 框架承诺 |
|---|---|---|
| 当前新写 | 新项目和新工作轮次只产生这一版本 | 完整维护、完整回归 |
| 可恢复 | 不再新写，但历史 active work 可以继续或安全退出 | 保留确定性读取、恢复和关键回归 |
| 可升级 | 没有 active work 时，可由受控动作进入当前版本 | 先诊断，PM 确认后迁移，不静默改业务事实 |
| 只诊断 / 清理 | 只识别遗留资产并给出处理入口 | 不允许旧资产重新进入主链 |
| 退休候选 | 已知消费仓不再依赖，且有替代路径 | 在明确版本节点删除读取、入口和测试 |

“能解析”不等于“支持新建”。主逻辑的目标是只接收当前模型；旧格式最终应停留在读取、恢复或迁移边界。

## 3. 已知消费仓

以下是 2026-08-11 的只读快照。扫描期间没有写入消费仓，也没有修改用户级安装态。批次二同样没有迁移这三个仓或升级 `~/.pmai`；仓名只用于兼容治理，不代表这些仓都应立即升级。

| 消费仓 | Doctor / 当前阶段 | 已识别合同 | 当前依赖 | 受控升级前置条件 |
|---|---|---|---|---|
| `ExampleAgentProject` | `invalid / iterating` | consumer schema/layout v1；5 个 legacy module | `成本与定价` 为 `stage=1 + designing`；`能力匹配卡` 为 `stage=1 + iterating + build v4`；active build 没有 `source_hash_version`，按 v1 hash 范围恢复 | 先保护现有 WIP；完成、取消或明确迁移 active work；不得给进行中的 build 静默换 hash 范围；再按 Doctor finding 逐项升级 |
| `ExampleConsumerApp` | `sync_required / iterating` | consumer schema/layout v1；3 个 split module | `租户开通与接管` 为 `stage=2 + iterating + build v4`；`product-onboarding-product-manifest` 为 `stage=1 + ready_to_build` | 先保护迁移和业务 WIP；分别处理 active build 与 ready 合同；split truth source 关系必须保留；无 active work 后再刷新宿主入口和布局资产 |
| `ExampleAgentProject` | `invalid / initialized` | 未标当前 consumer contract；缺 `AGENTS.md`、`project.yml` 和 Proposal | 依赖旧骨架识别与历史迁移入口；未发现可直接按当前主链继续的完整基线 | 先由 PM 确认仓是否仍使用；确认现有资料和 Git 基线；再制定一次性接入方案，不能把缺失事实自动补成“已完成” |

### 3.1 消费仓迁移规则

- 有 active work：优先按原合同恢复、完成或取消，不原地改写合同版本。
- 只有 ready work：先验证 ready currentness、目标路径和项目定义，再决定继续或返回 design。
- 没有 active work：可以在干净、已提交基线上执行一次受控升级。
- 有 legacy / split 声明：迁移必须保留原 truth sources 的业务含义，不能只为让 Doctor 变绿而重排文档。
- 仓是否仍在使用不明确：只诊断，不迁移。

## 4. 核心状态与构建兼容资产

| 兼容资产 | 当前读取者 | 当前新写 | 已知消费仓依赖 | 迁移动作 | 退休条件 | 主要回归 |
|---|---|---|---|---|---|---|
| 旧 `stage` | `_lib/work_contract.py` 唯一兼容读取；state/status/preamble/Doctor 只消费 canonical projection | v5 已停止新写 | `ExampleAgentProject`、`ExampleConsumerApp` 的 active work 均仍有 stage | 旧仓只投影为 display stage，不据此覆盖明确 lifecycle | 所有已知 active work 结束或升级；支持窗口内只剩 stage fixture；PM 确认删除 | `test-state-lib.sh`、`test-status-view.sh`、`test-build-contract.sh`、`test-consumer-doctor.sh` |
| 顶层 `lifecycle_state` 与 `build.lifecycle_state` | `_lib/work_contract.py` 唯一校验并输出 canonical state | v5 build 前只写顶层，build 开始后只写 build 内状态 | 两个 active v4 消费仓都依赖双位置一致性 | v1-v4 恢复保持原 shape；冲突值失败关闭，不自动修复 | 所有已知 v1-v4 active work 清零并经过支持窗口；PM 确认删除 | `test-state-lib.sh`、`test-status-view.sh`、`test-build-contract.sh`、`test-consumer-doctor.sh` |
| build contract v1 | `_lib/work_contract.py` 将缺版本解释为 v1；旧 close 路径可读 | 新工作只写 v5 | 本次已知 active work 未发现 v1 | 仅允许历史 close / 诊断；无 active work 时回 design 生成新合同 | 已知仓与支持窗口内均无 v1 active work；历史 close 恢复入口有替代或明确停止支持 | `test-build-contract.sh`、`test-close-work.sh`、`test-consumer-doctor.sh` |
| build contract v2-v3 | `_lib/work_contract.py` 统一读取；`finalize-work.py` 明确转交 `build-close` 恢复 | 新工作只写 v5 | 本次已知 active work 未发现 v2/v3 | 保留恢复，不升级进行中的合同；完成或取消后下一轮直接写 v5 | 支持窗口内 v2/v3 active work 为零；`build-close` 不再承担对应恢复 | `test-build-contract.sh`、`test-close-work.sh`、`test-land-work-v2.sh`、`test-consumer-doctor.sh` |
| build contract v4 | `_lib/work_contract.py` 统一读取；finalize / landing 可按原 runner 状态恢复 | 新工作只写 v5 | 两个已知 active build 当前均为 v4 | 保留双 lifecycle、`required_checks`、旧 evidence 和 runner 游标原样恢复，不就地升版 | 已知 v4 active work 清零；支持窗口结束；真实恢复证据完成；PM 确认删除 | `test-build-contract.sh`、`test-finalize-work.sh`、`test-land-work-v2.sh`、`test-consumer-doctor.sh` |
| 缺 `source_hash_version` | `context-pack.py`、`ready_contract.py`、`build-contract.py` 将缺失解释为 v1 全量 hash 范围 | 新 ready / build 写 `source_hash_version=2` | `ExampleAgentProject` 的 active v4 build 明确依赖 | 本轮结束前继续按 v1 范围验证；不得静默换 hash；显式回 design 后的新批准写 v2 | 已知 ready / active work 均显式为 v2；缺字段 fixture 只剩历史读取测试 | `test-ready-contract.sh`、`test-context-pack.sh`、`test-v2-currentness.sh`、`test-shared-currentness.sh` |
| 旧 v4 `browser-smoke / visual / behavior` evidence | `build-contract.py` 旧审计读取与 evidence validator；build / finalization 文档保留恢复路由 | 新 Web build 只写统一 `browser-acceptance` | 两个 active v4 仓在恢复前需逐项确认其 final checks，不能预判为新链 | 原合同已有哪组 checks 就按哪组完成；不把旧 evidence 改名伪装成新批次 | 已知 active v4 全部完成；没有 resumable 合同仍引用旧三项；发布窗口结束 | `test-build-contract.sh`、`test-finalize-work.sh`、`test-close-work.sh`、`test-browser-acceptance.sh` |
| `required_checks` 别名 | `_lib/work_contract.py` 唯一兼容读取并映射为 `final_checks` | v5 build 与 acceptance profile v3 已停止写入 | 当前 v4 合同普遍存在，不是个别仓异常 | v1-v4 恢复继续读取；v4 与 final_checks 不一致时失败关闭 | 所有支持内 active work 完成；无宿主或恢复路径依赖；PM 确认删除 | `test-build-contract.sh`、`test-status-view.sh`、`test-finalize-work.sh`、`test-consumer-doctor.sh` |
| 模块级或缺失 `audit_dir` | `build-contract.py`、`finalize-work.py`、`prototype-boundary.py` 回退 `.pm-workflow/audits/<模块>` | 新轮次写包含唯一 work id 的隔离目录 | `ExampleAgentProject`、`ExampleConsumerApp` 的 active v4 在恢复前需核实具体目录 | 进行中合同沿用原目录；新一轮不复用旧 artifact | 已知 active work 均使用 work-id 隔离目录或已结束；旧目录只剩归档 | `test-build-contract.sh`、`test-finalize-work.sh`、`test-land-work-v2.sh` |
| 旧 v4 `final_check` 无 runner 游标 | `finalize-work.py` 允许没有 `finalize-run.json` 的旧 final_check 直接按原状态落地 | 新 finalize 会写 runner marker 与 timing | 当前扫描未发现已进入该形态的明确实例 | 保持原 evidence，不补造 currentness / final-validation 时间线 | 支持窗口内不存在无 runner marker 的 resumable final_check | `test-finalize-work.sh` |

## 5. 消费仓布局与项目定义兼容资产

| 兼容资产 | 当前读取者 | 当前新写 | 已知消费仓依赖 | 迁移动作 | 退休条件 | 主要回归 |
|---|---|---|---|---|---|---|
| consumer schema/layout v1 | `consumer-doctor.py`；模板 `.pm-workflow/config.yml` | 新消费仓仍写 v1，当前不是历史包袱 | `ExampleAgentProject`、`ExampleConsumerApp` | 保持当前；未来升版时必须另建 v2 迁移计划 | 不退休；只有出现 v2 后才重新定义支持窗口 | `test-consumer-doctor.sh`、`test-doctor-skills.sh`、`test-init-project.sh` |
| 未标版本 consumer contract | `consumer-doctor.py` 识别为 `unversioned`，只给兼容声明建议 | 新仓不写未标版本 | `ExampleAgentProject` | 先确认模块关系和真相源，再只更新 config 合同；不自动搬业务文档 | 已知仓均声明 layout version；Doctor 不再需要 unversioned 推断 | `test-consumer-doctor.sh`、`test-doctor-skills.sh` |
| module `legacy / retired / split` 声明 | `consumer-doctor.py` 读取 `consumer.compatibility`；active `.work-meta.json` 优先 | 仅 brownfield 按确认后的真实关系写 | `ExampleAgentProject` 有 5 个 legacy；`ExampleConsumerApp` 有 3 个 split | 逐模块保留原 truth sources；完成内容重整后才能改为 current | 对应模块已转 current，或仓明确退役；索引与 truth sources 均已提交 | `test-consumer-doctor.sh`、`test-doctor-skills.sh` |
| 缺 `project.yml` 时 config / `CLAUDE.md` marker fallback | `project-type.py`：先读 `project.yml`，再读旧 config，最后读 `auto-detected` marker | 新项目只由首个 ready design 写 `project.yml` | `ExampleAgentProject` 明确缺 `project.yml`；其它 active 仓应在迁移前再次核实 | 有可建造 design 时由 PM 确认后生成定义；不能从当前请求猜类型 | 已知可用消费仓均有合法 `project.yml`；旧 marker / config 不再存在 | `test-project-type.sh`、`test-project-definition.sh`、`test-consumer-doctor.sh` |
| 旧 Startup 规则与无标记 `AGENTS.md` | `consumer_entry.py`、`consumer-doctor.py` | 新模板写唯一托管区块 | `ExampleAgentProject` 已只读验证为可迁移的 `legacy_migration`；`ExampleAgentProject` 缺入口 | PM 确认后仅替换托管区块，保留项目补充；未知 PMAI 规则和 symlink 失败关闭 | 已知消费仓均为当前托管区块；旧规则 parser 经过一个发布窗口 | `test-consumer-doctor.sh`、`test-init-project-codex-compat.sh` |
| 分散的生成器 / 消费仓 marker 判断 | `repo-kind.py` / `_lib/repo_identity.py` 现统一输出 `generator / consumer / uninitialized`；preamble、status、Doctor 与 Kimi 遗留 dispatcher 复用 | 新入口只消费统一三态；`PMAI_PROJECT_INITIALIZED` 仅保留兼容投影 | 不改写消费仓；旧入口可能仍只认识布尔初始化状态 | 上层逻辑逐步改读 `PMAI_REPO_KIND`；解析器缺失或异常时 PMAI 路由失败关闭 | 所有活跃入口只读三态；兼容布尔值无外部依赖后删除 | `test-repo-kind.sh`、`test-narrative-mode.sh`、`test-kimi-host-compat.sh`、`test-doctor-skills.sh` |

## 6. 恢复、迁移与旧入口

| 兼容资产 | 当前职责 | 已知依赖 | 下一步 | 退休条件 | 主要回归 |
|---|---|---|---|---|---|
| `/pmai-build-close` / `close-work.sh` | v2/v3、旧 v4 和中断后的 finalize / landing / docs 恢复 | 真实调用频率未知；active work 仍使其具备恢复价值 | 保留手动入口；统一 Loop Contract 后再收窄到明确恢复场景 | 不再承担支持窗口内旧合同；新 finalize 的恢复路径覆盖全部中断点；PM 另行确认公开入口变化 | `test-close-work.sh`、`test-build-close-hard-gates.sh`、`test-land-work-v2.sh`、`test-finalize-work.sh` |
| `project-type.py` | 当前定义读取器中的历史 fallback | `ExampleAgentProject` 可能需要；active 仓需复核 | 先把 fallback 隔离成 legacy adapter，再考虑删除 | 所有已知消费仓完成 `project.yml` 升级；主链无调用旧 config / marker | `test-project-type.sh` |
| `migrate-reqs-to-modules.py` | 历史 `requirements/active|closed` 的只读 inventory；`--apply` 明确拒绝 | `ExampleAgentProject` 等旧骨架可能命中 | 保留 dead-end guard，不宣称能自动迁移 | 支持窗口内无旧 requirements 树，README / CHANGELOG 不再指向它 | `test-migrate-reqs-to-modules-compat.sh`、`test-pm-facing-surface.sh` |
| `migrate-context-to-project.py` | 把旧 `docs/CONTEXT.md / PROJECT.md` 改成 `docs/PRODUCT.md` 的历史迁移器；目标位置已不符合当前仓根 `PRODUCT.md` 合同 | 本次扫描未确认真实依赖；`ExampleAgentProject` 只能先盘点，不能假定适用 | 先从当前升级入口隔离；未审查和改造前不得在现行消费仓执行，也不能由 Doctor 自动调用 | 已知仓无旧名；status 不再提示；脚本归档或改成当前合同后有确定性回归 | `test-narrative-mode.sh` 只覆盖旧提示，缺迁移行为回归 |
| `migrate-context-v4.py` / `migrate-prd.py` | 更早 `docs/CONTEXT.md`、单文件模块和 v5 草稿布局的迁移器，输入输出均早于当前合同 | 本次扫描未确认真实依赖 | 标记为隔离中的历史工具；不得进入当前自动升级链，也不得直接用于三个已知消费仓 | 已知仓无对应旧文档，且无当前文档指向后归档 | 当前无确定性回归，是退休前需要处理的测试缺口 |
| CLI `pmai status` | 已退休；健康检查统一走 `pmai doctor --check`，产品进度走 `/pmai-status` | 无当前依赖 | dispatcher 拒绝该命令，不保留包装器 | 已于 2026-08-12 删除 | `test-doctor-skills.sh` |
| `install-codex-hooks.sh` | 转发到 `install-project-hooks.sh --host codex` 的旧包装 | 旧消费仓 Startup 可能引用；入口迁移器明确识别 | 先迁移已知 `AGENTS.md`，再观察调用 | 已知消费仓入口已更新；模板和文档无引用；经过一个稳定发布窗口 | `test-init-project-codex-compat.sh`、`test-consumer-doctor.sh` |
| 项目级 Skill 副本与旧 Codex prompts | Doctor / uninstall 只诊断和清理，不再安装 | `ExampleAgentProject` 历史上出现过；当前是否仍存在需迁移前复核 | PM 确认后运行 `pmai uninstall --local <repo>`；全局安装继续清旧 prompt | 已知仓与用户级目录均无遗留副本；清理入口经过一个稳定发布窗口 | `test-doctor-skills.sh`、`test-skill-link-ownership.sh`、`test-private-onboarding.sh` |
| Kimi Code `pmai-*` Skill 与 PMAI managed hooks | 新 install / upgrade / init / Doctor repair 不再创建或刷新；Doctor 只报告，uninstall 保留显式清理能力；dispatcher 仅作遗留安全兼容 | 本轮未扫描或修改真实 `$KIMI_CODE_HOME`；已知消费仓依赖需迁移前核实 | 先确认没有以 Kimi 作为唯一恢复主控的 active work，再单独执行清理；保留模型、凭据、自定义 Hook 与普通配置 | 已知安装态和消费仓均无 PMAI Kimi 主控资产；经过一个稳定发布窗口后删除 manager / dispatcher 兼容代码 | `test-kimi-host-compat.sh`、`test-doctor-skills.sh`、`test-exec-adapters.sh` |
| OpenCode 全局 / 项目 `pmai-*.md` commands 与 `opencode.json` | 新 install / upgrade / init / Doctor repair 不再创建或刷新；Doctor 将遗留 command 归为非阻断 `legacy_compatible`；renderer / uninstall 仅作兼容工具 | 本轮未扫描或修改真实 OpenCode 配置和三个消费仓 | 逐仓确认无唯一恢复依赖后移除 PMAI 托管 command/config；Builder adapter/profile 保留 | 已知安装态和消费仓均无 PMAI OpenCode 主控资产；经过一个稳定发布窗口后退休 renderer 和主控兼容测试 | `test-opencode-host-compat.sh`、`test-consumer-doctor.sh`、`test-doctor-skills.sh`、`test-exec-adapters.sh` |

## 7. 飞书兼容资产

飞书是官方维护的可选能力。它的 schema 支持窗口不应阻断完全不用飞书的 PMAI 核心版本，但使用飞书时仍必须失败关闭。

### 7.1 当前写入版本

| 资产 | 当前写入 | 当前兼容读取 |
|---|---:|---|
| `review.json` | v3 | v2、v3 |
| `apply-plan.json` | v4 | review v3 + plan v3/v4；legacy review v2 + plan v2 |
| `resolutions.json` | v4 | v3、v4 |
| `comment-actions.json` | v3 | v1/v2 通过受控升级器进入 v3；新能力只允许 v3 |
| `remote-verification.json` | v2 | 只接受 v2；旧 v1 必须重跑远端验证 |
| `remote-native.json` | v1 | v1 |
| remote coverage | v2 | v2 |
| `handoff.json` | v2 | v1、v2 |
| handoff bundle | v2 | v2 |
| checkpoint / replan candidate | v1 | v1 |

### 7.2 迁移和退休规则

- 已有 v3 ready 批次可以按原流程恢复，但 reply-only 等新能力必须新建 v4 批次。
- legacy review/plan v2 只用于完成原批次，不允许借旧 schema 使用 v4 新语义。
- remote-verification v1 不视为有效证明，必须重新执行远端回读。
- handoff v1 必须保留 replan candidate 绑定；缺绑定时失败关闭。
- 退休某代 schema 前，`list-resumables` 与 `list-handoffs` 必须证明已知 main 和 attached worktree 中不存在对应未完成批次，并经过至少一个稳定发布窗口。
- 主要回归：`test-lark-review.sh`、`test-lark-adapter.sh`、`test-lark-entry-routing.sh`、`test-publish-to-lark-e2e.sh`。

## 8. 兼容退出门

任何兼容项只有同时满足以下条件才能从清单移入删除批次：

1. 已知消费仓扫描为零依赖，或依赖仓已明确退役。
2. 不存在使用该版本的 active / ready / resumable work。
3. 当前版本已经停止新写该格式。
4. 迁移或恢复动作经过真实消费仓验证，并保留 Git 证据。
5. README、Skill、Doctor 和错误提示不再把用户导向旧入口。
6. 对应兼容测试可以删除或改为“拒绝已退休版本”的测试。
7. 退休节点写入 CHANGELOG，并说明最后可升级版本和失败提示。

## 9. 下次更新触发条件

出现以下任一事件时更新本文件：

- 新增或发现消费仓。
- active work 的合同版本、生命周期或 hash 范围发生变化。
- 运行了一次消费仓升级、恢复、取消或退役。
- 新版本停止写某个兼容字段。
- Doctor 新增或删除兼容 finding。
- 飞书批次 schema 升版。
- 准备删除任何兼容读取、迁移脚本、旧入口或对应测试。
