# CHANGELOG

PM-AI-Workflow 生成器仓的演进记录。本文件**只记影响下游业务仓的改动**——
`scripts/` / `skills/` / `templates/` / `agents/` / `hooks/` 等同步到业务仓的内容；
不记 `tests/` / `docs/归档/` / `RUNTIME.md` / `TODOS.md` / `INVARIANTS.md`
等仅生成器仓内部用的文件。

> **入口**：业务仓续 active req 或起新 req 前，先看顶部"已发布版本"段确认是否需要
> 跑同步流程（`框架同步-SOP.md`）。
>
> **写作约定**：
> - 时间倒序；最新在顶部
> - 每条形如 `<commit-short-sha> <type>(<scope>): <一句摘要>`
> - 重大改动追加详细说明（影响范围 / 迁移指引）
> - 仅记影响业务仓的改动；纯生成器内部改动可省略

---

## 未发布

- `fix(doctor)`: **消费仓诊断改为按布局版本、模块状态和 finding ownership 判断，不再把旧文档组合等同于内容损坏。** 机器合同复用现有 `.pm-workflow/config.yml:consumer`，不新增平行 manifest；fresh init 声明 layout v1，标准索引仍固定为 `docs/INDEX.md` 与 `docs/modules/INDEX.md`。未标版本旧仓的非空 `spec + decisions`、合并式 `spec` 会进入待确认兼容项，`legacy / retired / split` 可在 PM 确认后只记录格式或现行真相源；active `.work-meta.json` 始终按 lifecycle 严格校验，空白三件套、缺失产品脊柱和不可恢复 active work 仍阻断。项目声明的归档目录生效，标准索引明确链接的旧顶层文档可保留，非空目录不依赖 `.gitkeep`。JSON finding 新增 `kind / blocking`，区分框架托管同步、合法旧产出、待确认兼容和真实内容损坏；CLI 保留完整分类并让 `consumer_invalid` 优先于升级或宿主同步。升级或同步不能迁移、补写或生成空白业务文档，兼容关系只能在 PM 逐项确认后写入现有配置。

- `refactor(status+doctor)`: **产品进度与框架运维入口彻底拆开。** `/pmai-status` 只回答产品进度、当前模块和下一步；新增 `/pmai-doctor`，默认只读检查全局框架、Claude / Codex / Kimi / OpenCode 宿主入口和当前消费仓，并以稳定 JSON 返回 `healthy / upgrade_available / consumer_sync_required / consumer_invalid / broken`。消费仓诊断按阶段检查根目录产品脊柱、`docs/` 归位与索引、模块三件套、`project.yml` 声明的真实实现根和入口、`mockups/manifest.json` 与看板、active build 恢复资产、Git 可携带性、旧结构和敏感配置跟踪风险；不执行项目命令、不读取 token、不逐字比较可编辑文档。OpenCode 项目入口与 Git pre-commit hook 新增只读 `--check`。全局入口修复必须显式使用 `pmai doctor --repair`，消费仓刷新、文件迁移、legacy 清理和升级仍需 PM 二次确认。`/pmai-upgrade` 只执行已确认升级。CLI `pmai status` 降为 `pmai doctor --check` 的弃用兼容包装，不再维护第二套检测；跨版本 doctor 继续把参数和行为完整交给目标安装版本。

- `fix(review)`: **最近一轮 P1/P2 复审统一补齐决定、宿主、验证和飞书同步边界。** 决定问句只有出现明确“结论 / 决定 / PM 回答 / 状态”时才闭合，普通业务动词不再被推断成 PM 已拍板；开放问题扫描会忽略代码围栏和 HTML 注释里的假章节。repo-local `pmai status` 只把目标版本的宿主隐藏清单当数据读取，项目 hook 检查与原子写入始终执行当前可信 checkout 的代码；Kimi 配置 symlink 的提交和回滚增加 referent 内容 CAS，外部并发修改不会被覆盖。全量 runner 强制 skill eval 的唯一摘要、失败数与退出码一致，杜绝 `failed > 0` 仍假绿。飞书 frontmatter 标量拒绝 CR、Unicode 换行和非法 key 注入；同秒评论 checkpoint 按评论自身事件时间登记 ID，回复水位不再提前吞掉新评论。

- `fix(integrity)`: **决定闭合、待清理事务和全局安装生命周期统一按证据失败关闭。** 开放问题会继续识别“待定 / 不确定 / 未知 / 仍需讨论”等占位回答；决定正文按先后顺序处理候选、未决声明和正式结论，无问号的决定状态问句不会进入当前决定，规范性的“不得 / 禁止 / 防止作废”也不会误判为已作废。cancel / land 的 prepared 清理记录新增唯一事务身份，同分支事务拒绝互相覆盖；cleanup 只使用一次捕获的主线 commit 做状态与祖先验证，并通过同一 `git update-ref --stdin` 事务校验主线 ref、按旧 OID 删除 build ref，主线 reset 时保留恢复现场；master-only 仓库也可正常取消。全局 install / upgrade / doctor repair / uninstall 共用 OS 级锁，拿锁后原位进入真实 CLI，保留 PID、控制终端和原生信号语义；等待锁时的中断、继承 fd 准备失败和锁验证失败都有稳定退出码且不会继续自愈或卸载。upgrade 只有在工作树已确认 clean 或 dirty 内容已进入 stash 后才允许 `reset --hard` 回滚，并恢复原 branch 或 detached HEAD 和全部宿主入口；status、stash、snapshot 或信号在保护完成前失败时保留本地改动。Kimi 普通文件、live symlink、dangling symlink 与缺失状态都先 claim 原目录项再从隐藏恢复舱分类，跨版本 manager / doctor 不再直接写穿用户 referent，也不会因 symlink 换绑混用入口和目标；所有 forward / restore stage 都在写入前登记并集中清理。install clone 后使用目标版本入口策略，并在目标 doctor 与 manager 复验通过前对 Host、Codex prompts、OpenCode、Kimi 配置和新 clone 保持可回滚；隐藏备份不会再被 managed glob 提前删除，提交后的恢复材料、日志和提示状态清理失败只保留明确 warning。doctor 只用真实路径判断跨版本归属，宿主目标仍按用户配置的 `PMAI_HOME` 精确校验，`/tmp` 等系统路径别名不再误报；OpenCode command 和 Kimi repair 结果都会二次验证，目录类型或文件写入错误会直接失败，不再报告假成功；远端检查在 stock macOS 缺少 GNU `timeout` 时复用 `gtimeout` / 直接执行兼容路径。

- `fix(portability)`: **macOS 与旧版 Bash 的关键宿主路径统一按真实平台能力执行。** 飞书正文发布不再依赖 macOS 无法作为子进程 cwd 的 `/dev/fd` 路径，改为通过已绑定目录 fd 进入原目录，父目录换名或 symlink 改向后仍不会误读其它正文；Kimi 在 Git 不可用时回溯仓库标记会显式停在 `/` / `//`，不再卡住整个 hook，prompt-build 共享预算也改用可跨 Python 3.9 进程比较的系统单调时钟；项目 Host 安装与跨版本 doctor 兼容 Bash 3.2 的零参数调用。待清理队列把缺失分支视为合法空身份、真实 Git 查询错误继续失败关闭；决定状态只接受完整的作废断言，不再把“已作废订单”或“不再有效入口”等业务对象描述误判为当前决定失效。

- `fix(reliability)`: **回归走查统一收紧清理恢复、宿主失败关闭、目标版本审计、飞书写回和决定语义。** 待清理队列的事务 stage 改用不与 `.pending-*` 中断标记重叠的命名空间；cancel / land 在主线变更前持久化 prepared 意图，提交后只激活队列，每项固定自己的 main/master integration ref，并以入队 branch OID 恢复和重验 landed 证据，分支删除使用 old-OID `git update-ref` CAS，因此主线 reset、分支改向、删除失败或进程中断都保留现场。Kimi 的 stdin 读取与 active-build guard 共用一份宿主总预算；分发器先以进程 cwd 路由，普通仓读取 stdin 前 no-op，只有 PMAI 路由内的超限、坏 JSON 与 payload 跨根失败关闭。repo-local `status` 按目标 `PMAI_HOME` 的入口策略审计，`doctor` 跨版本时委托目标安装，目标 doctor 缺失或不可执行则停止；项目 hooks 不再信任可伪造环境布尔值，只有绑定锁文件同一 device / inode 且实际持有排他锁的继承 fd 才能进入事务，原子删除在 claim 后遇父目录改向会通过固定 dirfd 按 inode 恢复正式名。飞书普通 Path API 接受 `/var` 等合法父目录别名但仍拒绝最终 symlink，联网阶段继续要求 canonical path；create / update / fetch / comments / api 统一拒绝失败 envelope，已发起 overwrite 后的非零、空、非 JSON、失败或不完整结果统一清除旧发布基线且不回显 stdin 正文。term-detector 在 heading / list / quote / fence / 缩进代码处结束无前导竖线表格；决定解析排除条件、时序和属性描述，空开放问题 section、空题名和占位回答不能通过，尚在讨论或仍为问句且没有明确结论的决定不能进入 active，带状态副词的明确否定保持有效。相关测试改为直接、精确断言，去掉空问题和数量下限造成的假绿。

- `fix(skills)`: **Skill 路由与对外承诺按真实用户意图收口。** design / spec-writing 不再按“写规格”等关键词机械分流：产品对象、范围、规则、信息结构、任务路径、权限或关键交互无法证明已闭合时先由 design 讨论，已经拍板的内容和纯文档整理才进入 spec-writing；补差过程中发现产品决定缺口也统一返回 design，不再留成正式规格里的待确认项。direction 收窄为方向重定和无序待办整理，并在流程内调用 meta，不让 PM 手工切入口。README 删除完整 Skill 菜单，只保留初始化、design → build 和迷路时的 status；宿主入口由共享策略统一过滤，`build-close`、`publish-to-lark` 虽不进入正常主路径，但作为兼容恢复和明确手动发布能力继续在 Claude、Codex、Kimi、OpenCode 可解析。飞书回执隐藏同步模式、revision、checkpoint 等后台协议；feedback 明确只有 Codex 当前会话定位经过验证，humanize 将二次复核准确称为独立上下文冷读。

- `fix(runtime)`: **入口文档、脚本行为和后台执行合同重新一致。** quick-fix 现在只允许从主仓 `main` 且仓库没有 active build 时启动；即使已经回到 main，只要存在 active build 也会在创建临时分支前拒绝，并引导回原 build 继续。build-cancel 与 land 只把工作环境加入待清理队列；main/master 上允许变更的 Skill 可在安全位置自动清理，但 status 和会话 startup 使用只读 preamble，不消费清理队列或中断标记。其它会话仍以该 worktree 为 cwd、worktree 存在 tracked / untracked / ignored 内容或 Git 拒绝删除时都保留队列，不能再用文件系统强删绕过 Git 保护；prepared/active 记录持久化主线引用和 branch OID，cleanup 在删除前重验原 activation，最终以 old-OID CAS 删除分支。仓库控制的 `.pending-*` 文件名和 JSON 值只通过 argv 与数据解析，不再拼入 Python 源码。`pmai status` 使用完整生成器标记，不会因消费仓恰有 `scripts/init-project.sh` 漏掉项目 hooks 检查，也不再隐式运行 update-check、联网或写缓存。build-cancel、quick-fix、direction、record、status、codebase-audit 与消费仓模板统一尊重显式 `PMAI_HOME`，不再二次写死 `~/.pmai`。

- `fix(context)`: **已有代码接入和 landed 后术语对账只使用可靠证据。** codebase-audit 只把代码盘点和 PM 确认的模块现状写入 `CODEBASE-AUDIT.md` / `PRODUCT-STATE.md`，不再从代码生成目标 `spec.md`、固定 coverage reviewer、视觉门或“8 段视觉基线”。term-detector 接入 landed 后的 `doc-impact.py init`，只从 build 规格锚点、landed 的模块 / 功能型规格、当前有效定名决定和 `kind=term/role` 的 accepted delta 识别候选；讨论稿、索引、真正已被替代的决定、引号、加粗和代码命名不会被升级为长期术语。当前新决定声明 `supersedes` / “已取代旧决定”时仍提取其中的新术语，不再把取代方向读反；删除线旧决定可由“未作废 / 未由新决定取代”或 `not yet / never superseded` 等明确状态恢复为有效，可能、提议和规范性表达仍不改变状态。句尾带“吗 / 么 / 嘛 / 呢”的内容仍按问句排除，重复决定 cue 通过单次线性扫描归位，不再随输入规模退化；术语表无论是否有前导 `|` 都能识别数据行。白名单读取显式 PMAI 安装资产，已登记项读取消费仓根 `PRODUCT.md`；detector 已确认仍缺失的术语不会因 `PRODUCT.md` 恰有其它改动而误判为已覆盖。

- `fix(upgrade)`: **升级、降级和项目 Host 配置刷新形成明确合同。** upgrader 每次加载目标或回滚版本的入口策略前先清除当前 Bash 进程残留函数；降级到尚未定义过滤函数的旧版本时恢复旧版全公开语义，真实 `--to <旧 tag>` 不再被新版策略和 doctor 误阻断。doctor 日志默认使用唯一 `mktemp` 文件，成功清理、失败保留，不再通过固定 `/tmp` 路径跟随 symlink。全局 upgrade 只更新框架源、skills 和 hook 源；已有消费仓的 Claude / Codex 项目配置由 `pmai status` 只读检查，再用 `install-project-hooks.sh` 精确刷新 PMAI 自有 hook，用户自定义配置保持不变。

- `fix(build)`: **active build 的自然语言查看与问题检查继续沿用原 build contract，不再掉进无范围通用 QA。** `status-view.py --execution-context` 只读派生并校验当前模块、lifecycle、target、`delivery_policy`、批准路径、accepted deltas、iteration/final lane 和 `project.yml` 命令；policy、类型、入口或路径漂移时失败关闭，多个 active build 只返回歧义，不猜模块，legacy v2 继续按项目类型派生保守恢复策略。新增 `active-build-guard.cjs`，Codex / Claude Code / Kimi Code 在 `building / iterating / final_check` 时把“启动看看 / 还有什么问题 / 继续改”等自然语言续回 `/pmai-build`；只对 prompt 首 token 的真实 `/pmai-*`、`$pmai-*` 或 `/skill:pmai-*` 命令放行，否定、引用、行内代码、代码块和文档示例不能绕过。Git / status-view 超时、非零、空输出、非法 JSON、未知状态、stdin 超时、读取错误或超过 4 MiB 都不会被误当成“无 active build”。内部时间预算低于宿主 hook timeout，确保慢路径来得及输出不可用护栏；Kimi 分发器对可信 hook 缺失、Node 启动失败和任意非零退出同样失败关闭。Kimi 的 review 与 build prompt hook 独立注册，避免拼接两份 JSON，OpenCode 由消费仓入口规则主动读取同一只读上下文。检查继续复用现有 `spec + decisions + accepted deltas + delivery_policy + acceptance lane`，没有新增问题分类合同或第二套持久化状态。`context-pack.py` 与 `check-open-questions.py` 只接受独立、肯定的“无未决问题”声明，空 section、空题名和占位回答仍保持 unresolved。新增真实会话 `019fdb65-d295-7450-80eb-62695bdff74d` eval 与 prototype/product、多 active、policy 漂移、跨宿主安装回归。

- `fix(hosts)`: **项目 hook 同时收紧信任源、失败语义和自定义安装路径。** Kimi 仓库内的生成器 / 消费仓标记只决定路由，不决定脚本来源；dispatcher 始终执行其自身所属 PMAI checkout 的 `hooks/` 与 `scripts/`，仿冒生成器仓不能借用户级 hook 执行，可信 hook 缺失或运行失败时也不能吞错放行。当前 Kimi 由同一 session cwd 启动 hook 并生成 payload，因此进程 cwd 是读取 payload 前的路由源：ordinary repo 直接 no-op，PMAI repo 才校验 payload cwd、大小和 JSON；write 的相对路径按 payload cwd 解析为绝对目标，`file_path` / `path` 必须一致。Claude Code / Codex 模板改用 `${PMAI_HOME:-$HOME/.pmai}`，项目安装器把实际 resolved root 纳入精确所有权迁移；非默认安装在宿主继承 `PMAI_HOME` 时可直接执行，同时仍保留同 basename 的用户自定义 hook。安装器先预渲染全部 Host，再用唯一备份事务写入并逐次复核内容、权限和 symlink 指向；stage、backup 和 cleanup 从 prepare 到 commit / rollback 都携带创建时的 device / inode，提交前先转入随机 claim 再核验，陌生同名文件不会被安装或删除；父目录在 rename 后改向也会先补偿自有命名空间再返回并发错误。失败时只回滚仍属于本轮且经正式路径提交的内容，不覆盖路径名上的并发编辑，Bash 3.2 空数组路径也可执行。该 CAS 不覆盖 claim 后通过旧文件描述符继续写入的版本，此类 writer 需共享写锁或版本保留。独立合法生成器 checkout 仍可命中生成器护栏，普通仓继续 no-op。

- `fix(lark-review)`: **飞书最新原生版本成为评审回收的唯一底稿，并补齐内容 / 格式防丢与批量收口合同。** collector 固定同一 revision 的 Markdown 与 full XML，把 block ID、样式、资源 token 和引用映射写入 `remote-native.json`；评论采集后的版本围栏只重读轻量 Markdown，不重复下载同 revision 的整篇 XML。`common_ancestor_compatible` 只决定能否做 raw diff，不再允许从旧本地 L 初始化目标。remote-coverage schema v2 为每个 R→T 删除 / 改写 / 移动同时绑定文本与结构：先按章节匹配，再只把双方剩余且全局唯一的同语义单元识别为跨章节移动；标题层级、列表顺序/缩进、表格角色、章节移动、真实重排及 paragraph→heading 等跨 kind rewritten 都计入结构高风险并强制预览，普通前插不误报，旧 v1 账本不能继续 apply / verify。改写必须绑定至少一个当前 T 的有效语义单元并保留原生格式，内容、格式任一未达到 100% 即阻断 seal。remote-only 正文和 legacy 整体归位必须有 PM 本轮明确确认；飞书正文、评论、回复均视为不可信业务证据。`decision_routing` 要求每个来源显式选择不写、新建或 supersede 决定，写入目标只允许仓内单一模块 decisions。collect 在联网前绑定唯一 canonical 仓根；最终正文、checkpoint 和 baseline 通过逐级 `O_NOFOLLOW` 目录 fd 原子替换，发布期间不重新按路径读取源文件；失败输出不回显 stdin 正文。精细写回后 `verify-sync` 同时比较文本与结构投影，并逐 block 验证格式 hash、资源 token 与引用映射。`complete-comments` 通过整批稳定围栏和逐笔回执收口，`solve_requested` 只有存在系统 solve 写回执时才能恢复。checkpoint 复用同 ready plan、同 revision 的格式验收；各阶段继续记录耗时和 API 往返，机器路径目标 10–15 分钟。

- `fix(harness)`: **初始化与 CI 不再依赖开发机隐含环境。** `init-project.sh` 在写入目标目录前校验 Git author / committer 身份，缺失时给出可直接执行的配置命令；初始 commit 的其它失败不再吞掉 Git 原始报错，并明确保留文件后的恢复步骤。GitHub Actions 显式配置测试身份；负向内容断言统一使用系统自带 `grep`，避免 runner 缺少 `rg` 时把“命令不存在”误判为“未发现违规”。

- `fix(harness)`: **补齐第一优先级的验证可信度与失败恢复。** `tests/run-all.sh` 现在通过标准库 runner 为每个 suite 设置独立超时，严格校验唯一 `Passed / Failed` 摘要和退出码一致性；摘要缺失、零用例、超时或 runner 异常都会失败关闭。全量入口额外实际运行全部 static / session skill eval，默认明确列出未配置 runner / judge 的 skip，`PMAI_REQUIRE_SESSION_EVALS=1` 可把缺失外部能力升级为 gate failure。生命周期回归补齐 `ready_to_build → building` 正向开工、`final_check → merge → docs_pending → resume` 不重复验收 / 合入，以及 cleanup 失败恢复与重复执行幂等。`land-work.sh` 在 main 落地状态、计时、暂存或 commit 失败时 abort 半合并态并保留隔离环境；legacy `close-work.sh` 的 commit 失败会恢复 `.work-meta.json`；待清理队列改为原子替换，损坏 JSON 不再被当作空队列覆盖。

- `fix(finalize)`: **最终化提速改为删除重复工作，不再把验收和文档准备前置。** 新 build 的 Web final checks 把 `browser-smoke / visual / behavior` 合成一个不可 exception 的 `browser-acceptance`，由 `browser-acceptance.py` 调用一次 gstack `browse chain` 批量验证受影响的独特流程、交互后断言和真实截图；旧 v2/v3/v4 合同仍按原三项证据恢复。新增可续跑的 `finalize-work.py`，按 v4 lifecycle 自动补 currentness、隔离命令验证、浏览器批次、evidence、review-ready、accept 和 landing；audit 游标绑定 commit/source hash，语义检查交回当前主控后不会重复 currentness，并以 `semantic-validation` 自动覆盖等待和判断耗时。runner 只提交当前模块状态和 audit 目录，拒绝混入其它 staged 路径；worktree 合入后立即输出 main 模块恢复游标，隔离环境进入安全待清理队列，端到端可从 documenting 续跑到 complete。`final-validation.py` 改在 `implementation.root` 执行，并只对完全相同的命令做一次执行、多检查记账；`build-contract.py commit` 对真实 Git commit 立即阻断批准范围外路径。文档影响地图只列 PRODUCT-STATE、accepted delta 明确影响的真相源和 landed diff 已修改文档，后者自动 covered，未受影响文件不再逐份打开写 no-change。landing 在 merge 前检测 main 未跟踪同路径；build/browser 缺陷、PM 新反馈、merge 冲突、未跟踪路径碰撞和文档碰撞都会在 timing 中退出或重置 10 分钟正常路径，runner 完成前校验适用阶段齐全。build contract 继续使用 v4，不迁移 project.yml，也不引入 candidate evidence。

- `fix(harness)`: **第一阶段可靠性硬化，把五项数据与生命周期安全规则下沉到运行时。** install / upgrade / uninstall 现在只会替换确认为 PMAI 所有的 host `_shared` symlink，遇第三方目录或 symlink 直接保留并停止；`--allow-existing` 在首次写入前一次列全 PMAI 同名目标，不再覆盖已有 `PRODUCT.md` 等资料。active work 查询改为由元数据声明所属分支的 attached build worktree 覆盖 main 旧副本；`build-contract.py start` 必须消费 current `ready_to_build + project.yml`，并拒绝路径穿越、绝对入口、目标或项目类型漂移，不再自动补 `.work-meta.json`；cancel 要求 main 干净且只提交当前模块 `.work-meta.json` 删除，不再顺带提交模块内未确认改动，提交失败时自动恢复状态文件且不进入清理流程。新增对应对抗回归，并把 ready contract suite 纳入全量编排。

- `feat(lark-review)`: **新增 `/pmai-lark-review`，把规格发布后的飞书二次评审接回 PMAI 产品主链路。** 新入口先将发布基线 B、采集时本地 L、采集时飞书 R 固定为只读证据，经处置账本归位出独立目标 T；只有 seal 的 T 能通过原子 apply 写入正式规格，版本门禁位于 quick-fix / design / build 分流之前且没有 force。评审批次持久放在项目私有且 Git 已忽略的 `.pm-workflow/context/lark-review/`，中断后优先恢复，只有 checkpoint 与下游生命周期都完成才清理。collector 以连续两轮稳定的已解决 / 未解决全量评论扫描建立围栏，并严格拒绝畸形分页响应；apply 前再复核 B/L/R/T、发布基线、正文及评论围栏，避免把飞书版和本地版混成一份规格。Docx revision 不再被当作正文作者或认可证明：只有 PM 本轮明确说由自己修改 / 已认可时自动接受，否则一次展示整批正文差异并只问一次是否认可。评论 `applied` 必须实际编译进 T，手工 `merged` 不能退化为完整 L/R；整批反馈按最高影响复用 quick-fix、active build 迭代或 design/build，不拆出平行生命周期。apply 后先把候选决定或 accepted delta 正式归位；精细同步第一笔写入前重新 fetch，并确认最新 revision 与 apply plan / expected revision 一致，所有写操作继续携带 expected revision。规格、决定和原型验证后，评论统一由 `complete-comment` 回复、解决、回读，并在同批 `comment-actions.json` 写受控回执；局部评论必须有结果文本，只有无法回复的全文评论可 solve-only。checkpoint / reopen 只消费该回执，不再接受 Agent 自填 reply、author 或 solver，PM / 协作者手工解决不能冒充本批完成或被系统重开。`publish-to-lark` 现在以写前 revision 栅栏覆盖，并只对写操作返回 revision 建立发布基线；表格合并首个写入失败后停止后续 revision 串联。`lark-sync` 的精细同步和回拉也刷新同一基线。旧文档可 legacy 降级，已记录 revision 却无法读取、文档身份冲突或并发变化时 fail-closed；frontmatter 写入只补丁 PMAI 标量并原子替换，保留未知 YAML、注释和并发产生的本地正文；`im-markdown` 只在 `lark-cli >= 1.0.58` 时开放。

- `feat(build)`: **Kimi Code 加入外部构建工具选择，同时保留当前主控排除规则。** 消费仓默认 builder 配置新增 `Kimi Code（k3, adaptive）`；`builder-profile.py`、build contract 和执行器适配器现可识别 `kimi-code`，通过 Kimi 原生 `--prompt + --auto` 在已确认的构建环境中非交互执行。旧消费仓缺少该 profile 时由运行时补齐，不改写项目配置。Codex、Claude Code、Cursor Agent 或 OpenCode 作为主控时，本机 Kimi 可进入 build 卡片；Kimi 自己作为主控时仍排除同名外部 profile，只保留“当前会话直接构建”和其它工具，避免递归启动。

- `feat(feedback)`: **新增 `/pmai-feedback` 作为消费仓到 PMAI 框架仓的唯一会话反馈出口，并移除职责漂移的公开 `/pmai-skill-improve`。** 新入口只读复盘当前原始会话，对照消费仓已确认设计和实际使用体验，区分项目问题、执行偏差、Skill 缺口、框架合同缺口与宿主限制，再生成一段带消费仓路径、会话 ID、原始会话绝对路径、证据位置和框架冷读要求的可复制 Prompt。新增 `current-session.py` 通过当前宿主确定会话 ID 精确定位原始记录；Codex 使用 `CODEX_THREAD_ID` 并同时检查 active / archived，会话不唯一、cwd 不匹配或宿主链路未验证时直接阻断，禁止按最近修改时间猜测。旧 `skill-feedback/` 历史档案保留，其现状对账、问题归位和 PM 拍板纪律已吸收到新交接合同；design / meta 路由、README、doctor 和安装暴露面同步切换到 `/pmai-feedback`。

- `feat(kimi)`: **Kimi Code 成为 PMAI 一等主控，并完全使用宿主原生 Skill 入口。** `pmai install/upgrade` 现在把公开 Skill 暴露到 `$KIMI_CODE_HOME/skills/pmai-*`，Kimi 中直接输入 `/skill:pmai-init-project`、`/skill:pmai-design`、`/skill:pmai-build` 等命令，不模拟 `/pmai-*` slash command。生成器仓与消费仓的 `AGENTS.md` 明确三条使用链路；当前主控识别新增 `kimi-code`，会排除同宿主外部 profile。Kimi 只有用户级 `config.toml` hooks，因此新增带标记区的原生 hooks 管理器和按仓库类型路由的全局分发器：普通仓 no-op，生成器仓接文档/review 护栏，消费仓接写保护/review guard；安装、升级、卸载、doctor、status 全链路同步管理且保留用户原配置。

- `fix(build)`: **把 PM 看原型期间的快速修改与定稿后的完整验收拆成两条执行车道。** 真实消费仓会话表明耗时主要来自每轮小改都重复 production build、完整浏览器验收、dev server 恢复和外部 builder 启动，而不是 Next.js 编译本身。acceptance profile schema v2 现在分别输出 `iteration_checks / final_checks`；build contract v4 新增 PM `request-finalization` 硬门、两层 evidence 和 `resume-iteration`，定稿前机器拒绝 final evidence 与 `review-ready`。active build 的文案、布局、按钮和局部交互默认由当前会话直接处理，只做热更新、typecheck 与当前页面走查，复用同一 dev server / 浏览器并先回“已修改，可刷新查看”；外部 builder 只用于首次实现或大型重构。PM 明确定稿后，`final-validation.py` 才在冻结 commit 的 detached worktree 运行一次 project.yml test/typecheck/build，避免污染 active 构建缓存；`build-timing.py` 记录分阶段耗时和 time-to-preview，2–5 / 5–10 分钟只作预警。

- `fix(build)`: **给 prototype 增加持久的实现深度合同，阻止 AI 按最终规格静默建设真实系统。** `spec.md` / PRD 继续定义最终产品语义，不另造“原型规格”；`acceptance-profile.py` 根据 `project.type` 编译 `delivery_policy`，新 build contract v3 固化 policy 与 hash。`/pmai-build` 在首次实现、每轮反馈修改和中断恢复时都把实现深度置于规格之前重新交给构建工具：原型的用户可见路径与交互做真，数据库、鉴权、外部集成、异步任务等底层默认模拟。新增不可 exception 的 `prototype-boundary` required check 与 `prototype-boundary.py`，候选定稿前扫描批准范围外改动、数据库 migration、生产基础设施、密钥配置、真实鉴权和外部副作用信号，并要求 AI 明确完成 diff 语义复核；模拟底层能力不再被原型 coverage 误判为漏实现。旧 v2 合同继续用于中断恢复兼容。

- `fix(build-close)`: **把完整验收前移为 build 的验收就绪候选，close 只做确定性落地。** 真实消费仓中一次 `/pmai-build-close` 从调用到完成约 30 分钟；实际 merge 只需数秒，主要耗时来自 close 才首次走完整浏览器路径、发现规格漏项后补业务代码、重跑 production build、重新分析文档影响，以及开发服务占用 worktree 导致清理失败。现在 contract v2 新增 `review-ready`：候选实现必须在 `iterating` 阶段完成全部 required checks、逐项规格覆盖和文档影响草案，形成绑定当前 source hash / implementation commit 的快照；`accept` / `complete` / `validate-land` 拒绝缺失或过期快照，`final_check` 不首次跑完整验收也不修改业务代码。`land-work.sh` 会把运行进程或缓存占用导致的 worktree 清理失败转入安全待清理队列，不再阻塞 landed 后文档同步；文档提交会自动纳入 `doc-impact.json`，不再需要 amend 补交。

- `fix(build)`: **把“当前会话直接构建”恢复为常驻选项。** 上一轮为避免 Codex 主控再次启动 Codex CLI，把当前主控对应的外部 profile 从候选中排除；实现同时把当前会话亲自构建误降成了“外部工具全不可用时才出现”的兜底。现在继续排除与当前主控相同的外部 CLI，但 `builder-profile.py list` 始终返回 `native`，开工卡无论本机还有多少外部工具都会展示“当前会话直接构建”；推荐逻辑仍优先遵循项目 builder 配置，没有可用外部工具时才默认推荐当前会话。

- `fix(build)`: **开工卡一次展示有效环境与工具，并排除当前主控。** 真实 Codex 消费仓会话中，`builder-profile.py` 只检查本机命令是否存在，导致 Codex 主控把 `Codex（gpt-5.4, high）` 推荐成外部构建工具；同时 PM 必须先点“调整”才能看到其它选项。现在 `recommend / list / resolve` 都要求当前主控，推荐和候选统一排除同名执行器；开工卡直接展示环境说明、推荐工具和全部本机可用工具，没有其它外部工具时才回退为“当前会话直接构建”。Gemini CLI 的 profile、适配器、合同枚举、模板、文档和测试一并移除。

- `feat(memory+design)`: **新增用户级个人经验记忆，并把 SSO 场景清单从通用 design 规则迁出。** 项目事实、决定和偏好继续留在消费仓现有真相源；跨项目仍成立的高信号纠偏在闭合后写入 `${PMAI_STATE_HOME:-$HOME/.pmai-state}/personal-memory.sqlite3`，后续 design 在确定性 context pack 之后单独召回候选，按相关性、适用性、重复关系和独立检查价值自适应选择，只作后台检查，不参与 `source_hash`，缺库或失败时继续运行。正常召回不设固定条数；字符预算和高位候选上限只作异常保护，频繁超限应合并碎片经验。重复证据会合并增权，明确“以后都这样”直接高权重生效，错误经验可降权、取代或遗忘；`pmai memory status/search/show/forget/export` 提供旁路控制。此前写入 design 的“持续新增、SSO / 导入 / 同步、属性变化与退出”固定清单已删除；其背后的集合变化经验只迁入当前用户存储，不作为新用户默认 seed。

- `fix(design)`: **跨日恢复时刷新执行规则，并修复第三次消费仓复盘暴露的辅助漂移。** 同一 design 会话跨日、切换主控、会话压缩恢复或安装版本可能变化时，必须重新读取当前 design skill 和必读规则，不能继续沿用旧消息中的快照。同时修复 context reconstruction 残留退役 `--target`、新模块 `designing` 不建目录、已确认标题误报未决、非决定章节混入 active decision 四项漂移，并以真实会话 eval 和确定性测试固化。第三次复盘中的 SSO / 持续运营经验已按上条归入用户级个人经验，不再作为通用设计硬检查。

- `fix(design+build)`: **把可建造状态升级为可验证的依据与目标范围合同。** 第二次真实消费仓复盘发现，权限规格已经更新但模块没有重新建立正式 design 状态，旧 Product Manifest 仍显示“可以构建”；同时 build 要求精确目标路径，design 的 ready 记录却只存 hash / revision / checkpoint，导致执行器只能临时猜页面。现在 design 在 ready 时必须同时提交最新 context pack 和精确 `approved_target.paths`；build 开工前重新编译上下文，通过共享 currentness 校验确认 source hash 未变化，并只能复用 design 批准路径；status 使用同一结论，过期 ready 改为引导回 design。目标路径已有未提交改动时在创建环境前阻断，无关 WIP 继续保护。context pack 对缺少新 `.gitignore` 规则的旧消费仓自动写入 Git 本地 exclude，不再制造未跟踪缓存。

- `fix(design)`: **收紧决策节奏、业务化提问与跨模块 build 入口。** 真实消费仓会话中，design 把可推导事项拆成连续确认题，用“实例身份 / 公钥 / 激活申请”等实现词让 PM 判断，并在平台许可证与 Product Manifest 同时成文后只留下一个含糊的 build 指向；已有 `askuser-rules` 虽规定总量预览、一次一题和业务大白话，却没有被 design 直接列为必读。本次让 design 在进入、续跑或切换主模块后的首题前刷新上下文，后台过滤已有答案、机械项和可逆偏好，首题前报告真实决策总量；每题必须转成角色、对象和实际业务结果，PM 说“看不懂”时原问法作废。跨模块讨论固定一个主模块，把其它模块归为既有约束、同步规则或独立后续工作，一轮只留下一个明确 build 入口。`project-definition.py` 同时改为相同建造方案重复写入 no-op，技术方案未变时不再改文件或递增 revision；任何真实方案变化都要求 PM 明确重定义。

- `fix(codex)`: **Codex 统一使用原生 skills，退役重复的 custom prompts。** 旧版为了让 Codex CLI 模拟 `/pmai-*` slash 命令，会同时安装 `~/.codex/skills/pmai-*` 和 `~/.codex/prompts/pmai-*.md`；Codex Desktop 会把后者固定显示为 `prompts:pmai-*`，形成一整组重复且杂乱的入口。现在 Codex 只通过 `$pmai-*`、skill 选择器或自然语言调用原生 skill；`pmai install/upgrade` 会清理旧 prompt 文件，doctor/status 不再生成或检查它们，uninstall 继续兼容清场。Claude Code skills 与 OpenCode slash commands 不受影响。

- `refactor(spec-writing)`: **规格 / PRD 统一为指导研发实现的最终目标合同，不再由原型或 landed 实现反向定义需求。** 新口径把输入分为规范性来源、设计与实现证据、过程记录：已确认产品规则和决定决定最终要求；mockup、原型、代码、landed diff 只用于理解结构与发现缺口；备选、否决理由和过程只留在 discussion / decisions。删除 PRD 强制原型覆盖范围表、§六截图和 ASCII 兜底，不再把 mock、占位、部分落地或未覆盖写进正文。landed 后固定按“符合 / accepted delta / 漏实现 / 无依据实现”对账，只有 accepted delta 可以修改规格目标。同步把 `PRODUCT.md` 的“技术栈”节替换为“产品边界”，技术方案只由 design 定稿后的 `project.yml` 持有。

- `refactor(init+design+build)`: **项目建造定义从初始化延后到首个可建造 design，并退役固定验收链。** 初始化现在只收项目名、路径和一句话背景，只建立产品上下文与 host 配置；不再接收第四个 project-type 参数，不创建代码、prototype、mockup 看板、dev server，也不依赖 gstack。首个达到 `ready_to_build` 的 design 由 PM 一次确认建造对象和技术方案，通过新 `project-definition.py` 生成严格校验的 `.pm-workflow/project.yml`；`.pm-workflow/config.yml` 只保留 builder profile。build、context pack、builder 推荐、status 校验与 adaptive acceptance 统一读取新定义；active helper 不再提供绕过 `project.yml` 的 type/UI 默认入口，build contract 也不再默认 `prototype` 或固定检查集。Web required checks 必须有 active browser-smoke，v2 不能用 exception 跳过；gstack 可由其它 browser/Playwright 适配器替代。外围 mockup、mirror-site、quick-fix 和规格写作改为读取动态 build target，不再假设固定 `prototype/` 或 Next.js。删除旧 `build-audits.py`、coverage reviewer、工程结构探测/注入脚本、固定编排文档与测试；contract v1 validator、旧 config/`auto-detected: system` 读取和既有迁移入口继续兼容。

- `fix(build)`: **项目类型与验收退出每轮开工卡，只确认工作环境和构建工具。** PM 进一步明确：构建对象不是每轮需求临时推断，而是项目初始化时定义的项目性质；验收也不需要 PM 选择，应按项目类型和风险走框架默认。新项目现在只接受 `prototype / product`，写入 `.pm-workflow/config.yml:project.type`；`project-type.py` 让 build 静默读取，并对旧 `CLAUDE.md` marker 做渐进兼容。`builder-profile.py` 改为只给推荐，`/pmai-build` 开工卡固定只显示工作环境与构建工具，PM 可一次确认或调整；项目类型、验收方案、worktree、合同和证据数据不得显示。PM 选择当前环境时，main 写保护只放行 v2 合同声明的目标路径；工具失败换工具必须重新确认，不能静默替换。

- `refactor(workflow)`: **统一 design → build → PM 多轮修改 → 自动落地主线 → 主线后文档编译。** 来自真实消费仓长会话的反馈显示，旧链路把保存建造依据、worktree、执行器、手动 `/pmai-build-close` 和文档同步拆成 PM 需要理解的第二条工程流程；design / meta / mockup / spec-writing 也会重复提问、只复述、只画当前局部或漏掉关联页面。本次新增确定性 context pack 与共用 decision policy；build contract 升级 v2，统一 `designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`，prototype / product 只切换验收适配器；自然语言“定稿 / 可以提交 / 可以合并”直接授权完整检查、merge 和 landed 后文档同步；merge 冲突与 `landed/docs_pending` 可恢复且不重复 merge。四个关键 Skill 重构为 design 内部编排：meta 产出危险前提 / 反例 / 替代模型，mockup 覆盖完整任务和边界状态，spec-writing 用覆盖矩阵只编译已确认决定并支持 landed 后事实对账。新增 `context-pack.py`、`acceptance-profile.py`、`doc-impact.py`、`land-work.sh`、合同 / 状态 / 恢复回归，以及 `evals/cases` + `skill-eval.py` 的真实会话评测基线。`/pmai-build-close` 保留为兼容与恢复入口；合同 v1 继续可读，已有消费仓下次 design / build 渐进升级。

- `fix(build)`: **把主动 browser smoke 纳入 build-close 硬门**。PM 担心“gstack 安装/被 doctor 看见”不等于 runtime 里 `/browse` 真能启动；本次新增 `pmai doctor --browser-smoke` 和 `check-gstack-browser.sh --browser-smoke --json-out .../browser-smoke.json`，主动打开本地页面并写机器证据。`build-contract.py validate-close` 现在要求 `.pm-workflow/audits/<模块>/browser-smoke.json` 与覆盖 / 视觉 / 行为 / 合成报告一起齐全；`pass` 必须带 `active_browser_smoke=true`。主动 smoke 受限、跳过、失败或阻塞时，视觉 / 行为验收不能静默当通过，必须经 PM 明确接受并记录 `audit_exception` 后才能收尾；行为审 `fail` 仍一律阻断。

- `fix(dx)`: **补齐 devex-review 暴露的 4 个开发者体验缺口**。新增 `scripts/measure-tthw.sh`，把可自动量的骨架 smoke 和必须真实 dogfood 的首模块规格 TTHW 分开：`smoke` 跑 `init-project.sh` + `status-view.py --narrative`，`record` 把人工起止时间写到消费仓 `.pm-workflow/audits/tthw.jsonl`。`pmai whats-new` 规范版本展示，避免 `vv0.2.0`，默认输出收短并支持 `--max-lines` / `--full`。`detect-project-structure.py` 接受位置参数 repo 路径并为不存在路径输出 PM 可读修复提示。`check-gstack-browser.sh --smoke` 捕获并分类 Playwright Chromium 缺失、系统 Chrome app bundle 权限等真实浏览器启动失败；`--doctor` 明确只是 passive check，不再暗示 browse 一定可启动。

- `fix(skills)`: **补全未初始化项目的全入口护栏**。此前 `status-view.py` / `skill-preamble.sh` / 消费仓 `AGENTS.md` 已能提示“当前目录还没有 PMAI 初始化”，但部分公开 skill 和 Codex/OpenCode 直达 slash 路由仍可能绕过项目入口，继续尝试读取或写入项目产物。本次把 Codex prompts、OpenCode commands 统一改为先读项目 `AGENTS.md`、再跑 `skill-preamble.sh`，命中 `PMAI_PROJECT_INITIALIZED: 0` 时停止并引导 `/pmai-init-project`；同时给除 `/pmai-init-project`、`/pmai-upgrade` 外的公开项目型 skill 增加入口护栏。`/pmai-humanize` 保留窄例外：只处理粘贴文本或仓外文件且不写 PMAI 项目产物时可继续。

- `fix(init-project)`: **脚本层阻止重复初始化已接入 PMAI 的消费仓**。`init-project.sh` 现在会在 gstack 检测和模板写入前识别目标目录里的 PMAI marker（如 `AGENTS.md` / `CLAUDE.md` 中的 PMAI 入口、`PRODUCT-STATE.md`、`.pm-workflow/config.yml`、`.codex/hooks.json`、OpenCode PMAI commands 等）；命中后即使调用方误传 `--allow-existing` 也会退出，避免覆盖 `PRODUCT.md`、`AGENTS.md` 和 host 配置。正常资料目录接住逻辑保持不变。

- `feat(opencode)`: **新增 OpenCode 主控入口与 slash commands 安装**。PMAI 现在不只把 OpenCode 当 `/pmai-build` 执行器，也支持 PM 在消费仓直接用 OpenCode 打开项目并输入 `/pmai-*`。`pmai install/upgrade` 会生成 `~/.config/opencode/commands/pmai-*.md`，每个 command 只路由到 `PMAI_HOME` / `~/.pmai` 下的权威 `SKILL.md`；`init-project.sh` 会在消费仓生成 `.opencode/commands/pmai-*.md` 和 `opencode.json`，同时 `AGENTS.md` 改为 Claude / Codex / OpenCode 通用 agent 入口。OpenCode 第一版不伪装 Codex hooks，不生成 `.cursor/`；保护策略用 OpenCode permission、PMAI git hooks、build contract 和 changed-path review 兜底。`pmai doctor/status/uninstall` 同步检查和清理 OpenCode commands。

- `feat(build)`: **新增 builder profile 建造工具档位并接入 OpenCode 执行器**。PM 反馈 build 只问“用哪个执行器”不够，模型和思考深度等建造参数没有清晰确认；继续只补 `model` 会变成症状补丁。本次把 `/pmai-build` 的选择改为建造工具档位，PM 视图只展示 `工具名（model, thinking）`，例如 `Codex（gpt-5.4, high）`，并允许同一句回复覆盖模型和 thinking。`.pm-workflow/config.yml` 新增 `builder.profiles`，底层继续记录 timeout / sandbox / auto / trust 等执行参数；`builder-profile.py` 负责解析 profile 并生成结构化 snapshot；`build-contract.py` 写入 `builder_profile` 和 `builder`，供 `/pmai-build-close` 复盘。本次同时新增 `scripts/exec-adapters/opencode.sh`，并把 codex / cursor-agent / gemini adapter 接上对应隐藏参数。

- `fix(build)`: **补落地 / build / close 硬门，阻止混合交付绕过收尾**。真实会话复盘发现 PM 说“落地”后，AI 会把它解释成小改，直接把 `docs/modules/`、`mockups/`、`prototype/` 混在一条主会话里推进和提交，没有规范进入 `/pmai-build`，也没有 `/pmai-build-close`。改动：① `/pmai-design` 增加“落地意图识别”和 prototype 分流门，PM 说“落地 / 实现 / 提交”等必须先判断小改 prototype-only 还是转 build；② `/pmai-build` 收紧小改分支，只有单字段 / 单文案 / 局部样式 / 已确认弹窗微调且不改 docs/mockups 才能退出 build；③ `/pmai-build-close` 明确为主原型 + 模块文档 / mockup 的混合交付唯一收口，缺 build contract / 三道审 / PM 验收时不能伪装 close；④ 新增 `scripts/check-mixed-delivery.py` 并接入消费仓 pre-commit，普通提交同时 staged `prototype/` 或 `Sources/` 与 `docs/modules/` 或 `mockups/` 时会被拦下，正式 close 用 `PMAI_ALLOW_MIXED_DELIVERY=build-close` 放行。

- `fix(codex)`: **补 Codex CLI 直输 `/pmai-*` 的 slash prompt 暴露**。此前 `pmai install/upgrade` 只把 PMAI 暴露到 `~/.codex/skills/pmai-*`，Codex Desktop runtime 能发现 skill，但 Codex CLI 直打 `/pmai-status` 这类命令仍可能不走 slash prompt 入口。改动：安装 / 升级时同步生成 `~/.codex/prompts/pmai-*.md`，每个 prompt 只负责把 `/pmai-*` 路由回 `PMAI_HOME` / `~/.pmai` 下的权威 `SKILL.md` 并要求完整读取执行；`pmai doctor` 可自愈缺失 prompts，`pmai status` 报告 prompt drift，`pmai uninstall` 只清理 PMAI 管理的 `pmai-*.md`，不碰其它 Codex prompts。

- `refactor(design)`: **把 `/pmai-design` 收紧为设计主入口和分流中枢**。真实会话复盘发现 AI 容易跳过业务对象建模，直接进入 A/B 页面方案、文档成文或原型修改。改动：① design 增加“业务对象建模硬门”，进入方案前必须讲清原始输入、业务对象、对象关系、状态、下游判断和真相源；② 现有工作类型判断升级为分流硬门，产品判断不清转 `/pmai-meta`，视觉 / 结构有岔路转 `/pmai-mockup`，主原型修改转 `/pmai-build` 或 PM 明确小改确认，workflow / skill 问题转 `/pmai-skill-improve`；③ 强制停顿点覆盖对象链、需求类型、meta、mockup、spec、build；④ mockup 明确默认优先 gstack shotgun，gstack 不可用时走 PMAI 内部多方向比稿；⑤ meta 区分单主控多视角和多 Agent 压测，不可用子 Agent 时必须声明退化；⑥ 新增 `scripts/check-gstack-browser.sh` 并接入 `pmai doctor`，识别 Codex sandbox localhost `EPERM`，避免把 runtime 限制误判为 gstack browser 损坏。

### 框架瘦身改造（吸收 ExampleAgentProject 设计方法）—— 进行中

- `refactor(meta)`: **`/pmai-meta` 收敛为产品判断模型**。PM 进一步反馈：Office Hours 化、grill 分层和“会话纪律 + 三个思考引擎”仍像外部方法拼装，没有形成 PMAI 自己的内核。改动：① 主方法论定为“产品元思考 = 用追问和压测，把表层诉求建成产品判断模型”；② 模型固定为判断句、地基账本、判断标准、模型轴、分路；③ 保留旧 meta 原词和逻辑：第一性原理建地基账本，升维 / 换高度找判断标准，多视角压测模型和分路，UI 信息 / 任务 / 判断层服务页面模型轴；④ gstack / office-hours 的需求证据、现状对手、具体用户、最小切口、观察意外、未来适配只作为产品想法素材，grill 的一题一问、依赖决策树、推荐默认答案、短答追问、能从文件查到的不问 PM 只作为问法纪律；⑤ `/pmai-meta` 不 runtime 调 gstack，不把 office-hours / grillme 作为 PMAI 主品牌；⑥ design / doc-writing / spec-writing 边界和 meta 静态测试同步更新。

- `refactor(gstack)`: **补齐 gstack 旁路文档接回 PMAI 文档地图的执行门禁**。上一版结合合同只把 `/document-generate` / `/document-release` 定位为工程文档旁路，但“采用后必须回到 PMAI 文档地图”还停在规则层，直接跑 gstack 仍可能留下未索引文档或只引用 `~/.gstack/...`。本次补齐：新增 `docs/engineering/` + `docs/engineering/INDEX.md` 作为 README/API/CLI/架构/how-to/tutorial/reference 的接收点；消费仓 `CLAUDE.md` / `AGENTS.md` / 文档地图 / docs 索引模板写明旁路接回规则；新增 `check-engineering-docs-index.py` 并接入 pre-commit，采用后的工程文档未登记索引会阻塞 commit；README 和测试同步。

- `refactor(gstack)`: **新增 PMAI × gstack 结合合同，统一“专项能力层”边界**。PM 复盘发现 gstack 结合点分散：meta 是方法吸收、mockup 是视觉探索、build 是审计证据、doc-writing 的 PDF 出口又只写成模糊的“Markdown 转 PDF skill”，`document-generate` 也容易被误当成产品文档生成器。改动：① 新增 `skills/_shared/gstack-integration.md`，把结合方式分成方法吸收、能力调用、证据生产、可选旁路；② 现有 meta / init-project / codebase-audit / mockup / build / build-close / mirror-site / doc-writing 引用统一合同；③ doc-writing 和 deliverables 模板明确 PDF 出口是 gstack `/make-pdf`，源 Markdown 仍是 PMAI 真相源；④ `document-generate` 定位为工程文档旁路，不承接产品介绍、PRD、模块规格或 PM 汇报材料；⑤ README 把 gstack 从无条件硬依赖改为“能力层（部分流程必需）”，并说明已有代码库接入不阻塞。

- `refactor(meta)`: **`/pmai-meta` v2 改为问题会诊入口，拆分产品想法、PMAI workflow 与已有材料压测三条路径**。PM 反馈第一版 Office Hours 化仍然像小修补：没有真正吸收 gstack / grillme 的 gate 和测试，且把 `lark-doc-edit / publish-to-lark / pmai-lark-sync` 这类 PMAI workflow 决策误导到 `/pmai-design`。本次改动：① 主 skill 改为薄入口，先读资料，再选择产品想法会诊、PMAI workflow 决策或已有材料压测；② 新增 `product-idea-framing.md`，承接产品想法沉淀里的现状对手、需求证据、具体用户、最小切口和失败预演；③ 新增 `pmai-workflow-decision.md`，要求先读相关 skill，再比较调用现有、改现有、新建入口、先不做，skill 改造落点明确为 `/pmai-skill-improve`；④ `problem-framing.md` 收敛为 Read / One Question / Premise / Alternatives / Coverage / Handoff 六道门禁，Alternatives 后必须停住让 PM 选；⑤ 下游 design / build / spec-writing / doc-writing 引用同步为问题会诊和已有材料压测口径；⑥ 新增 `test-meta-v2-routes.sh`，防止新 skill 偏置、Alternatives 抢跑和 workflow 改造误入 design。

- `refactor(mockups)`: **`/pmai-mockup` 改为 PMAI 编排 + gstack 视觉探索 + 本地看版接回**。PM 反馈 mockup 发散性不够，且内置 codex 出图路径不稳定、容易把 PMAI 拖成设计工作台。改动：① mockup 生成前先列几条产品设计方向，要求方向在结构 / 密度 / 路径 / 气质上真不同，并让 PM 先拍要画哪些方向；② 视觉气质探索优先调 gstack `/design-shotgun`，但 gstack 只负责生成和反馈，最终必须接回 PMAI `mockups/`；③ 新增 `scripts/import-mockup-variants.py`，把 gstack designs 目录或 PM 上传图片复制进 `mockups/`、更新清单并供看版生成器展示；④ 暂时移除 `/pmai-mockup` 内置图片生成能力，不再在 skill 中调用 `scripts/gen-mockup-image.sh` / codex image_gen；⑤ 允许 PM 上传截图 / 设计图作为设计素材进入看版，但不绕过 `/pmai-design` 直接变成规格事实。

- `feat(lark-sync)`: **新增 `/pmai-lark-sync`，把本地规格与飞书在线文档同步做成安全分流入口**。飞书文档不再默认等同发布缓存：skill 先判断真相源和同步方向，再选择精细修改飞书、整篇覆盖发布、飞书回拉本地或只 diff。精细修改复用 `lark-doc-edit` 的块级编辑和回读方法；整篇覆盖继续调用 `/pmai-publish-to-lark`；飞书回拉只保留本地追踪 frontmatter 并以飞书正文为准。`/pmai-publish-to-lark` 定位收窄为整篇发布 / overwrite 执行能力，README、doctor 清单和 spec-writing 飞书出口同步。

- `fix(build)`: **收顺 `/pmai-build` 的 PM 视图和执行器失败恢复**。PM 反馈真实 build 里连续被“固定设计上下文”、缺 `.work-meta.json`、执行器卡住、kill 进程、dev server 参数试错和浏览器失败刷屏打断。根因是 build 把内部状态、执行器排障和工具细节当成 PM 决策暴露。改动：① 构建前提示从“固定设计上下文”改为“保存本次建造依据”，只把本模块规格 / 决策 / 已确认看版做成建造起点；② `build-contract.py start` 在模块和功能锚点明确时自动补最小 `.work-meta.json`，不再要求 PM 额外确认内部状态文件；③ 执行器选择改成“独立建造工具”，明确 Codex 是另起 CLI、不是当前对话；④ `claude-code` adapter 增加状态目录、heartbeat、退出码文件和超时控制，build 流程要求 PM 窗口只报阶段摘要；⑤ 执行器失败默认保留半成品，由 PM 选接手补完 / 换工具 / 丢弃重来，禁止自动 `git restore .` / `git clean -fd` 清空落盘改动；⑥ dev server 命令改为以 `.pm-workflow/config.yml` 的 `{port}` 占位为准，不临场猜框架参数；⑦ build skill 路径口径改为“运行时变量 + 仓内相对路径”，禁止在框架规则、模板、prompt 或业务代码里写死 `/Users/...` 这类机器绑定路径。

- `fix(build-close)`: **收顺 `/pmai-build-close` 的合同补录、main WIP 和 PM 视图**。PM 反馈真实 close 里出现合同字段分两步补录互相覆盖、主仓有无关脏改仍被当成风险展开、沙箱验证失败刷屏、mock 看版是否退役不清楚等问题。改动：① `build-contract.py complete` 一次写齐 `implementation_commit` 和 `pm_accepted_at`，禁止并行跑 `commit` / `accept`；② `close-work.sh` 合并时用 `git merge --autostash`，main 上无关未提交 WIP 不再阻塞 close，也不会被塞进 close 提交；③ build-close skill 明确 PM 窗口只报阶段结果，不直播读文件、进程、日志和命令流水；④ mock 退役只改本次明确吸收的变体，不能猜着重写整份历史看版；⑤ 生成器入口和消费仓模板新增“禁止机器绑定路径”项目原则。

- `fix(build-close)`: **三道审证据接入 build 合同，没跑 browser / gstack 不再能 close**。PM 复盘发现真实 close 只跑了 `pnpm build`，没有正常调用浏览器验收也能合并。根因是三道审只写在 `/pmai-build` prose 里，没有进入 `build-contract.py validate-close`。改动：`validate-close` 现在要求 `.pm-workflow/audits/<模块>/coverage.json`、`visual.json`、`behavior.json` 和 `synthesis.md` 齐全；行为审 `fail` 直接阻断；视觉 / 行为审 `limited` 或 `skipped` 必须用 `build-contract.py audit-exception` 记录 PM 明确接受原因后才能收尾。`close-work.sh` 复用合同校验自动获得该硬门，测试 fixture 和 close 回归同步补证据。

- `refactor(spec-writing)`: **`/pmai-prd-writing` 收口为 `/pmai-spec-writing`，不保留兼容别名**。历史上已经把 PRD / spec 并入同一套“简要易懂”的规格写作模型；本次把未收干净的入口、目录、引用、doctor 暴露和测试收口：skill 目录迁到 `skills/spec-writing`，公开命令改为 `/pmai-spec-writing`，PRD 只保留为功能型规格文档的一种体例。

- `refactor(spec-writing)`: **重做 `/pmai-spec-writing` 的规格文档模型，PRD 和 4 列表格降为 preset**。PM 反馈改名后内部仍被 PRD 表格默认心智带偏。改动：spec-writing 改为“文档目标 → 规格模块 → 功能需求写法 → preset”的流程；规则收口、状态分类、流程、字段、权限、CRUD 分别选最清楚的写法；PRD 体例保留完整章节、§六 4 列功能表和 `check-prd-hierarchy.py` lint，但只在 PRD / 4 列功能表场景触发。共享 PM-VIEW §五从强制功能清单改为功能需求写法选择与表格 preset；few-shots 先锚定模块 spec / 待办风格，再给 PRD preset 示例；自定义产物路径和飞书发布路径提示统一优先仓内相对路径；测试锁定旧入口不存在、4 列表不再全局强制、PRD lint 不扩成模块 spec 通用 lint。

- `fix(spec-writing)`: **变更说明收成简要硬约束**。PM 反馈规格文档的变更说明必须简要写。改动：`/pmai-spec-writing` 在模块 `spec.md` 变更日志和 PRD §二变更日志两处明确“每条一句，通常 20 字内、最多不超过 30 字；只写改了什么，不写原因、过程、背景”，并同步 PRD 模板和写作规则，防止变更日志变成版本过程说明。

- `refactor(meta)`: **`/pmai-meta` 重做为 PMAI 问题对焦，停止复述式升维输出**。PM 反馈消费仓 meta 只是复述、没有主动追问和新思路；根因不是少一个 grill 分支，而是 meta 被写成分析工具箱，AI 容易直接套“对焦 / 推导 / 压测”模板输出。改动：保留 `/pmai-meta` 命令名，主定位改为问题对焦对话入口；先读资料、再一题一问、追问表层答案、挑战最危险前提、给 2-3 个替代方向，并在 Coverage Check 后降回 `/pmai-design`、`/pmai-doc-writing`、`/pmai-spec-writing` 或 `/pmai-build`。旧的升维、第一性原理、多视角压测和 UI 信息 / 任务 / 判断层能力不丢弃，收进 `thinking-toolbox.md`；访谈方法用中性 `problem-framing.md` 命名，只吸收深度访谈、反方挑战和带资料追问这类方法的有效部分，不把外部概念当成 PMAI 文件名。

- `refactor(design)`: **`/pmai-design` 补后台驾驶内核，减少设计讨论跑题**。PM 反馈重做规格时 AI 容易在相关模块同步、mockup 和规格成文之间跳转，根因是 skill 有“读上下文 / 一步一停 / 必要时 mock”的原则，但缺少后台工作类型判断和本轮目标绑定。改动：`/pmai-design` 准备阶段新增工作类型判断（新建、重做、冲突对齐、补齐口径、呈现确认、成文写规格）和顺手动作边界；`design-method.md` 补事实底座与产品结构推进顺序，要求先分清当前权威口径、历史理由、引用材料和待确认缺口，再按服务谁的判断 / 动作、边界、触发、字段、状态、动作、消失条件、跨模块权威关系推进。PM 侧不新增固定流程汇报模板，回归测试锁定通用内核。

- `fix(mockups)`: **`/pmai-mockup` 生成前默认先对齐已有界面**。PM 反馈 mockup 不看现有代码 / 原型样式，导致设计稿和已有界面接不上。根因是 skill 只要求确认“放什么、谁看、怎么分块”，没有强制先看现有产品长什么样。改动：`/pmai-mockup` 新增步骤 1.5，生成前必须读取 `DESIGN.md`、相关 `prototype/` 页面 / 组件 / 样式、已挑定 / 待合并设计稿和模块约束；默认模式改为“贴合现有界面”，只有 PM 明确要求才探索新风格；无可参考界面时必须说明这轮是在先定基调。回归测试锁定该流程约束。

- `fix(mockups)`: **mockup 看版卡片点开后提供返回目录入口**。PM 反馈看版卡片进入单个设计稿后没有回到目录页的按钮。根因是卡片直接打开原设计稿文件，原页不由看版生成器控制。改动：`gen-mock-board.py` 现在额外生成统一查看页 `mockups/viewer.html`，卡片先进入查看页，顶部固定提供“返回目录”和“打开页面”；缩略预览仍直接内联原设计稿。`/pmai-mockup` 和 mockups README 模板同步说明，回归测试覆盖查看页生成和返回入口。

- `fix(shell)`: **补齐 shell 输出里 `$VAR` 紧跟中文标点的变量边界**。macOS bash 3.2 + UTF-8 locale + `set -u` 下，`$VAR。` / `$VAR）` 会被解析成被 UTF-8 字节污染的变量名并触发 `unbound variable`。本次把 `/pmai-build-close` 缺 worktree 提示、`pmai-whats-new`、消费仓 pre-commit 模板、`/pmai-build` 执行器提示、`/pmai-build-cancel` 提示和测试诊断里的高风险输出统一改为 `${VAR}`，避免错误提示路径自身崩掉；同步修正 `RUNTIME.md` 测试基线数字。

- `fix(build)`: **`/pmai-build` 识别 DESIGN.md 兜底骨架，不再把缺视觉基线当成已可审标准**。已有代码接入会无条件兜底生成 `DESIGN.md` inventory 段，但视觉基线可能仍是“未建”状态；build 现在在动手前检测 `状态：兜底骨架` / `视觉基线段未建`，要求 PM 选择先跑 gstack `/design-consultation` 或手填视觉基线，或继续但将视觉门标成低置信，只挑明显 AI slop / 组件违和 / 可用性问题，禁止输出“视觉一致性通过”的强结论。同步补 `test-exec-adapters.sh` 回归；`test-init-project.sh` 也固化根目录 `PRODUCT-RULES.md` 初始化契约，防止真实安装态回退到旧 `docs/PRODUCT-RULES.md` 口径。

- `feat(skills)`: **增强 `/pmai-meta`：加入多视角压力测试模式**。`/pmai-meta` 统一为讨论前的对焦与压力测试入口：没锚点时先对焦或第一性原理推导，有锚点且 PM 想“多角度看看 / 找盲区 / 让几个 agent 分别看 / 对抗分析”时，生成少量互补视角做压测，再由主控合成根因、冲突和下一步。内置 agent 数护栏：默认 3-5 个、上限 7 个，简单问题可退化为主控多视角分析。框架不新增独立多 AI skill 入口，避免思考类命令膨胀。

- `refactor(design)`: **`/pmai-design` 方法论收敛并清理假 shared**。PM 反馈 design-card 只是卡片设计沉淀，不应伪装成通用设计逻辑；同时 `_shared` 里存在只有 `/pmai-design` 使用或混合了设计 / 写作职责的文件。改动：新增 `skills/design/references/design-method.md`，把当前 `/pmai-design`、design-card 经验和 gstack 式方向收敛提炼为"真问题 → 主方向 → 信息两面 → PM 顺序拍板 → 三件套"；Meta 作为对焦工具嵌入探索 / 设计段，不新增阶段。`module-questioning.md`、`info-design.md` 移出 `_shared`，保留为 design legacy reference；规格 4 问和定稿磨文纪律回到 `prd-writing/references/writing-rules.md`；`build-close` 显式 @读 `consistency-scan.md`，让该共享方法真实闭环；新增 `test-design-shared-boundary.sh` 防止 design-only 方法再次回流 `_shared`。

- `refactor(layout)`: **消费仓主文件回到仓库根目录，`docs/` 收敛为资料区**。PM 复核后确认：`PRODUCT.md`、`PRODUCT-STATE.md`、`PRODUCT-RULES.md`、`DESIGN.md`、`TODO.md` 是 PM 和 AI 每次进项目都要认的项目脊柱，必须在消费仓根目录；`docs/` 只放 `INDEX.md`、`modules/`、`decisions/`、`inputs/`、`deliverables/`、`archive/` 这类会增长的文档集合。同步改动：初始化脚本不再生成 `docs/PRODUCT.md` 等旧主文件；`docs/project-decisions/` 收短为 `docs/decisions/`；`docs/INDEX.md` 改为资料入口并链接回根目录主文件；main 写保护放行根目录项目脊柱和 `.pm-workflow/` 内部状态；docs 顶层守卫改为禁止主文件回流到 `docs/`。

- `fix(build-close)`: **补 build 合同，`/pmai-build-close` 不再靠当前分支 / worktree 形态猜收尾方式**。PM 反馈 datou 消费仓实战里 `/pmai-build` 没有记录执行方式和执行器，后续 `/pmai-build-close` 在普通实现分支上把“已提交但未合回、未完成验证”的状态说成“已收口”。改动：① 新增 `scripts/build-contract.py`，由 `/pmai-build` 在两道 PM 选择后写入 `.work-meta.json:build`，记录 `anchor` / `mode` / `executor` / `branch` / `worktree` / `baseline_sha`；PM 验收通过后补 `implementation_commit` 和 `pm_accepted_at`。② `/pmai-build-close` 入口先校验 build 合同，缺合同、缺实现提交、缺验收记录时停止补上下文；`mode=worktree` 但分支或 worktree 缺失时不退化成 main 直收。③ `close-work.sh` 改为只按合同决定 main 直收还是 worktree merge，未落主线不写“已收口 / 时间线已完成”。④ 消费仓 `AGENTS.md` / `CLAUDE.md` 模板和回归测试同步。

- `refactor(skills)`: **公开入口收敛：`codebase-audit` 降为内部子流程，`/pmai-deposit` 更名 `/pmai-record`，`/pmai-cancel` 更名 `/pmai-build-cancel`**。PM 反馈公开菜单里仍有“代码盘点 / 轻沉淀 / cancel”这类语义不清入口。改动：① `skills/codebase-audit/` 移到 `skills/_internal/codebase-audit/`，不再由 install / upgrade / doctor / status 暴露成 `/pmai-*`；已有代码接入、恢复和重扫都回到 `/pmai-init-project` 自动分流。② `skills/deposit/` 改为 `skills/record/`，共享分流文件同步改为 `record-routing.md`，README / 模板 / PM-VIEW 文案统一 `/pmai-record`。③ `skills/cancel/` 改为 `skills/build-cancel/`，只表达“放弃已进入 build 的工作”，设计讨论后暂不实现不再需要 cancel。④ doctor 全勤清单、install / upgrade symlink 重建、status drift 检测和回归测试同步跳过 `_internal`。

- `refactor(layout)`: **消费仓目录命名统一：`mocks/` → `mockups/`，`docs/归档/` → `docs/archive/`**。PM 拍板后，初始化脚本、新消费仓 `CLAUDE.md` / `docs/INDEX.md` 模板、文档地图、`/pmai-mockup`、`/pmai-build`、`/pmai-build-close`、`/pmai-record`、`check-branch` 写保护、docs 顶层归位守卫和 mockup 看版生成器全部改用新路径。模板文件同步从 `mocks-*` 改为 `mockups-*`；回归测试覆盖 `mockups/manifest.json` → `mockups/index.html` 和 `docs/archive/` 初始化 / 归位提示。

- `fix(build)`: **三道审结果只作为 `.pm-workflow/audits/` 内部记录，不在消费仓主结构里展开**。PM 反馈 `coverage.json` / `visual.json` / `behavior.json` 看起来像一组项目文档。确认后统一口径：三个 JSON 只落 `.pm-workflow/audits/<模块>/`，属于 `/pmai-build` 的内部证据；不写入 `docs/`，也不在中期项目主目录结构里展开。脚本输出、参考文档、初始化注释、`/pmai-build` 步骤说明和回归测试同步改为“内部审计目录”。

- `fix(mockups)`: **mockup 看版按需求归类并收掉 PM 低价值噪音**。PM 反馈消费仓 `mockups/index.html` 只按状态平铺，无法看出每组设计稿来自哪个需求，且页面露出清单文件、脚本提示、文件路径等无用信息。改动：`gen-mock-board.py` 改为先按 `requirement`（旧数据可从 `round` 兜底推断）分组，再在每个需求下展示多版设计稿；页面新增左侧需求目录和搜索，可按方向、亮点、轮次或路径过滤；卡片标题优先用 `title` / `explores`，路径只保留为“打开完整稿”链接；顶部去掉 manifest / 自动生成说明等技术噪音，固定文案改成 PM 可读的短说明。`mockups-manifest` 模板、`/pmai-mockup`、沉淀路由和 README 模板同步新增 `requirement` / `title` 字段说明，回归测试覆盖需求分组、旧 round 兜底、目录和搜索。

- `fix(status)`: **`/pmai-status` 输出改为 PM 行动视图，避免把内部诊断混成现状汇报**。PM 反馈 datou 消费仓实战里 status 输出难懂：一边说“没有 active work”，一边又说“实际工作区有未提交实现”，还把 `PRODUCT-RULES.md` 不存在当成近期决策说明。根因是 status skill 把脚本诊断、产品现状、模块决策和下一步建议混在同一层。改动：① `status-view.py --narrative` 在无进行中工作但 git 有未提交改动时，直接输出“有一轮改动还没收口”，建议先固定到独立分支或提交点，不再引导起新模块；② 多个进行中工作时按 PM 视图编号列出每项状态、当前步骤和下一步，不再输出 `active work` / worktree 等内部词；③ `/pmai-status` 输出合同改为“当前状态 → 产品现状 → 进行中工作 / 已定方向 → 建议下一步”，禁止“PMAI 状态脚本显示 / 记录层 / 可以理解为 / PRODUCT-RULES 不存在所以”这类话术；④ 增加 dirty main、多工作列表和 skill 文案回归测试。

- `fix(build)`: **`/pmai-build` 补构建前硬门，禁止用未提交设计上下文绕过 PM 两道选择**。PM 反馈 datou 消费仓实战中 build 没有询问“执行方式”和“执行器”，而是用“另开环境拿不到未跟踪 Docs/modules/ 和 mockups/”作为理由直接在 main 上实现。根因是 build 流程缺少“先固定建造依据，再问两道构建选择”的硬门。改动：① `/pmai-build` 新增步骤 0.5，检测 `spec.md` / `decisions.md` / `mockups/` / 功能型文档是否仍未提交或未跟踪；若是，只允许先 checkpoint 当前模块建造依据或停住，不得顺手提交无关未跟踪文件。② 步骤 1 / 步骤 2 明确空答 STOP，禁止默认“直接在主线上建”，也禁止把当前主控 AI 当默认执行器直接改代码。③ 消费仓 `AGENTS.md` / `CLAUDE.md` 模板同步要求 build 修改 `prototype/`、`Sources/` 或业务代码前必须拿到两道 PM 答案，回归测试覆盖该问题口径。

- `refactor(skills)`: **`/pmai-close` 更名为 `/pmai-build-close`，语义收敛为 build 验收后的收尾**。PM 反馈“close”的作用容易和 design 后定稿混淆：如果一轮只是把规格讨论清楚、暂时不实现，不应该再要求 close；但 build 完成后确实需要把最终原型带来的变更对齐回模块 `decisions.md` / `spec.md`、产品现状、术语和跨模块规则。改动：① skill 目录与 frontmatter 改为 `build-close` / `pmai-build-close`，doctor、banner 测试和消费仓模板同步；② `/pmai-design` 的 Next Up 改成三分流：进入 `/pmai-build`、先停住、或用 `/pmai-record` 轻量沉淀已稳定的项目级术语 / 规则 / 当前设计状态；③ `/pmai-build-close` 只在 `/pmai-build` 做完且 PM 验收通过后使用，仍负责提交 / 合并实现改动，并按最终原型对齐模块决策和规格；④ README、`templates/CLAUDE.md.tmpl`、PM-VIEW 共享规则和沉淀路由同步，避免把“讨论结束但暂不 build”误导到 build-close。

- `fix(skills)`: **`/pmai-meta` 升维通用化——从"找哪张账"放宽成"找更高的判断标准"，不再钉死企业经营语境**。PM 反馈"不太通用"——根因不是经营词库不够多，而是升维本质应按**这轮讨论到底在判断什么**选择标准；同一个对象在不同讨论里可能看经营、人生、工程、目标或认知标准，不能先按对象机械分类，也不能先替几个标准排主次。改动：① meta A0 从"类别表"改成**判断标准选择器**：经营判断→经营账本、个人使用价值→人生账本、工具长期使用→工程账本、取舍判断→目标账本、表达理解→认知账本；A2 第 3 问改为落到当前标准项，A3 / 输出格式全部改为按当前标准用词，禁错域词。② `references/词表与句式.md` 收敛为判断标准与表达护栏：保留禁用词、各域判断标准词库、"从 A 到 B"和旧范式校验，删除媒体标题 / 定位句生成职责。③ `/pmai-doc-writing` 承接一句话定位、标题和页首主张成文规则，可吸收 meta 的重定位结论，但最终由 doc-writing 成文。④ `/pmai-design` 触发关系收口：`module-questioning` 是探索段容器，`/pmai-meta` 是其中一种换高度方法；需求不真实也可以调 meta，当卡点在目标、标准、前提或表达太功能层时使用，调完必须降回段②理结构。

- `refactor(skills)`: **`/pmai-init-project` 收敛为项目初始化唯一入口，已有代码库自动分流到现状盘点；`/pmai-strategy` 更名为 `/pmai-direction`**。PM 反馈在已有 Swift/macOS 项目里初始化时，AI 把“跑代码盘点还是继续补 PMAI 骨架”做成菜单选项，还被 `gstack` 缺失带偏；根因是入口模型把“全新项目建骨架”和“已有项目接入”拆成两个 PM 要记的 skill。改动：`/pmai-init-project` A 步改为先判断项目情况，空目录 / 资料目录继续建骨架，检测到源码或 manifest 时自动进入已有项目接入子流程，不再让 PM 手动选择代码盘点；已有代码分支明确不调用 `init-project.sh`、不要求 gstack、不起空 `prototype/`。`codebase-audit` 定位降为 init 的内部子流程。公共 preamble / status 视图新增未初始化项目引导：其它 `/pmai-*` skill 被误调时先引导回 `/pmai-init-project`，不继续读不存在的 PMAI 文档；codebase-audit 明确作为 init 内部子流程时可在未初始化目录继续。事后方向入口从 `/pmai-strategy` 收口为 `/pmai-direction`，只暴露“方向重定 / 路线规划”两类意图；“已有代码接入恢复”不再作为 PM 菜单分类，只保留在 `/pmai-init-project` 的中断续跑语义里。二次扫同类残留后同步修正 `docs/INDEX.md`、`templates/TODO.md.tmpl`、`templates/CLAUDE.md.tmpl`、`project-questioning` 和回归测试，避免再次把已有代码首次接入指向手动代码盘点 或事后方向入口。gstack readiness 口径改为 `gstack` CLI 或 `~/.claude/skills/gstack` 任一可用即可，warning 只限定全新项目骨架分支，避免把“命令不在 PATH”误判成依赖缺失或把已有代码接入误报成阻塞。README 和回归测试同步防止退回“推荐 PM 改跑另一个命令”的旧体验。

- `refactor(skills)`: **写作入口分层补齐：`/pmai-humanize` 保留独立入口，`/pmai-prd-writing` / `/pmai-doc-writing` 承接结构、内容、文风整体优化**。PM 反馈实际很少单独跑 humanize，更多是让 spec writing / doc writing 查看某个文件并整体优化结构、内容、文风。改动：① `/pmai-humanize` 明确保留入口，但定位为表达层工具，只做去 AI 味、去黑话、顺句子，不接管结构重组和内容补差；② `/pmai-prd-writing` 新增“优化已有功能型文档”模式，按结构 / 内容 / 文风三层处理 PRD、功能需求、功能规格、模块 spec 等既有文档，最后复用 humanize 规则收口；③ `/pmai-doc-writing` 扩展为产品方向与介绍型文档成文器，支持产品方向 memo、产品定位说明、产品介绍、功能清单、优势说明、一页纸、汇报 / 决策材料；④ 调研并吸收社区 `content-strategy`、`copywriting`、`market-research`、`blog-writer`、`seo-content-writer` 等写作/策略 skill 的经验，加 `skills/doc-writing/references/product-direction.md`，把目标-受众-证据-取舍-异议-指标沉淀为产品方向六问、证据地图、产品定位/方向 memo/高管一页纸/决策材料模板。新增 routing 回归测试防止整体优化退化成纯润色。

- `feat(build)`: **`/pmai-build` 补齐 Claude Code CLI + Gemini 双体验执行器**。使用者可以继续采用“Codex 里 `/pmai-design` 落模块三件套，切到 Claude Code 跑 `/pmai-build`”的文件交接体验；也可以留在 Codex 主控窗口里选择 Claude Code / Gemini 作为 build 执行器。改动：① 新增 `scripts/exec-adapters/claude-code.sh`，当前 runtime 没有 Claude subagent 工具时用本机 `claude -p --permission-mode bypassPermissions` 非交互构建；② `/pmai-build` PM 工具选择正式露出 `Gemini`，并把 Claude Code 分流写清为“host subagent 优先、CLI adapter 兜底”；③ 消费仓 `AGENTS.md` fallback 从“subagent 不可用就请求换路径”改为“先尝试 Claude Code CLI adapter，再换 Codex / Gemini / 手动”；④ README 依赖表同步 Claude Code / Gemini / Codex 的 build 执行器角色。

- `refactor(docs+skills)`: **消费仓文档信息架构收敛**。新增 `docs/INDEX.md` 作为消费仓总文档索引，`PRODUCT-STATE.md` 只保留当前产品现状；项目级重大理路档案从 `docs/decisions/` 改为 `docs/project-decisions/`，默认不写，只在 `/pmai-direction`、`/pmai-build-close`、`/pmai-record` 或 PM 明确要求时经 PM 确认生成；保留 `/pmai-design` 的模块三件套 `docs/modules/<模块>/discussion.md` / `decisions.md` / `spec.md` 不变。`/pmai-prd-writing` 小改为功能型文档成文器：PRD、功能需求、功能描述、功能规格、功能评审稿默认直接落 `docs/modules/<按内容命名>.md`，并由 `docs/modules/INDEX.md` 索引；移除旧 `docs/prds/` symlink 收口机制和 `docs/独立PRD/` 默认路径。新增 `/pmai-doc-writing` 只写介绍型 / 表达型材料（产品介绍、功能清单、优势说明、一页纸、汇报材料），默认落 `docs/deliverables/`。`/pmai-build` 的构建锚点从“只支持模块 spec”扩展为模块 `spec.md` 或功能型文档。

- `fix(dx)`: **私有仓 onboarding 改成可验证路径**。README 默认安装入口从 public raw curl 改为 `gh repo clone` / SSH clone 后 `bash bin/pmai install`，raw curl 仅保留为 public mirror 路径；`install.sh` clone 失败文案补私有仓鉴权复核命令；`pmai install` / `pmai doctor` 增加非阻塞 gstack readiness 提示，提前暴露 `/pmai-init-project` 的外部依赖；新增 `test-private-onboarding.sh`，用当前工作树 snapshot 模拟私有仓安装、doctor、缺 gstack 阻塞和补齐 gstack 后初始化消费仓。

- `fix(i-mini)`: **清掉 I-mini / 双 host 入口里的旧 `.claude/scripts` 残留**。`/pmai-quick-fix` preamble 改回全局 `~/.pmai/scripts/skill-preamble.sh`，避免新消费仓没有 `.claude/scripts/` 时启动失败；生成器 `CLAUDE.md` 的 session 播报改为 `~/.pmai/scripts/status-view.py`；review/doc/jargon hooks 的注入文案改成 `.claude/settings.json` / `.codex/hooks.json` 双 host 表述；`/pmai-upgrade` 文案同步说明升级会重连 Claude + Codex 两边 skill symlink。新增回归断言防止旧 runtime 路径回流。

- `feat(codex)`: **补项目级 Codex hooks，完成 host hook 接入链路**。此前 Codex 只补了 `~/.codex/skills/pmai-*` skill 暴露和 `AGENTS.md` fallback，但消费仓仍只生成 `.claude/settings.json`，Codex 不会读取 Claude Code 的 hook 配置，导致 `check-branch.sh` 写保护和 `review-skill-guard.cjs` review/audit 约束注入在 Codex 主控下不完整。改动：新增 `templates/codex-hooks.json.tmpl` + `scripts/install-codex-hooks.sh`（merge 项目 `.codex/hooks.json`，保留既有非 PMAI hooks，幂等刷新 PMAI managed entries）；`init-project.sh` 新消费仓自动安装 `.codex/hooks.json`；`pmai migrate` 迁 I-mini 时同步安装；生成器仓根新增 `.codex/hooks.json`，Codex 协同改框架仓时也启用 review/doc/jargon hooks（不套消费仓 `check-branch.sh`）。文档和测试同步区分 Git hook、Claude Code hooks、Codex 项目 hooks；Codex 首次启用新增 hook 时可能要求信任确认。

- `fix(codex)`: **PMAI skill 同步到 Codex skill 目录，修复 Codex 里调不起 `/pmai-*`**。根因是安装/升级链路只重建 `~/.claude/skills/pmai-*`，Codex 只能靠 `AGENTS.md` 手工 fallback，无法在 Codex skill 列表里发现 PMAI。改动：`pmai install` / `pmai upgrade` 同步重建 `~/.claude/skills/pmai-*` 和 `~/.codex/skills/pmai-*`（支持 `CODEX_HOME` 覆盖）；`pmai doctor` / `pmai status` 同时检查 Claude + Codex 两边的 stale/missing/dangling 暴露；`pmai uninstall` 同时清理两边 symlink。消费仓 `pmai upgrade` 后，新 Codex 会话可发现 `pmai-*` skills；当前已打开的 Codex 会话可能需要新开线程/重启以刷新 skill 列表。

- `feat(codex)`: **补齐 Codex 三条使用链路入口**——生成器仓根新增 `AGENTS.md`，让 Codex 进本仓时能按 repo-local `skills/` / `scripts/` 协同改造框架，并可从本 checkout 执行 `/pmai-init-project` 初始化消费仓；消费仓 `templates/AGENTS.md.tmpl` 强化为明确的 Codex 主控入口，声明默认中文、消费仓定位、`PMAI_HOME` / `~/.pmai` 解析规则、`pmai-*` 特殊 skill 目录 fallback，并明确消费仓内不能重复跑 `/pmai-init-project`，后续走 `/pmai-design` / `/pmai-build` / `/pmai-build-close` / `/pmai-status`。新增 generator / consumer 两组 Codex 回归测试并纳入 run-all。

- `fix(skills)`: **`/pmai-meta` 输出纪律改「脑子里走流程、嘴上说大白话」——根治方法论黑话漏给 PM**。独立三 agent A/B 盲评（带 skill vs 无 skill 基线、第三方盲评不知情）实测：带 skill 答案更可落地、闸门也正确挡住不该拔高的小问题（综合 8.5 vs 7.5），但盲评挖出真缺陷——答案把"过闸门 / 升维 / 第一性原理 / 降回设计 / 哪张账"这些**内部方法论标签当章节标题漏给 PM**，被判工程黑话噪音、扣分（违反 PM chat 禁黑话铁律）。修法：把「输出格式」从带方法论标签的章节模板，改成两层——闸门 / 升维 / 第一性原理 / 五问是**脑子里走的流程**，**对 PM 只输出**①一句重定位结论（大白话 + 经营词，禁方法论词和黑话）②具体落地（出现 / 强调 / 隐藏 / 默认 / 第一步）；闸门没过直接答不摆流程；PM 主动要推导才亮过程。纯输出表达约束，不改思维流程本身。

- `feat(skills)`: **新增 `/pmai-meta`（换高度：升维 ↑ / 第一性原理 ↓）——讨论前的"对焦"工具**。PM 反馈：和 AI 讨论产品定位 / UI / 优先级 / 文案时，AI 容易停在"功能层"把话说得像产品介绍，或靠类比惯例做决定。本 skill 是一个**有闸门的思维流程**（不是一坨"说高级话"的提示词）：① **闸门**先判要不要换高度——纯执行细节 / 技术正确性 / 已明确小需求直接做，不硬拔高；② **升维 ↑** 把具体设计放进更高判断标准（现在在哪层 → 5 问：改变谁的决策 / 影响哪张账 / 从 A 到 B / 反对什么旧范式），措辞落到具体经营词（损益表 / 毛利 / 风险敞口）、禁黑话（重构 / 赋能 / 闭环…）；③ **第一性原理 ↓** 拆到不可再拆的基本事实、分清"真约束 vs 只是惯例的假设"、只用真约束重推、对比现状；④ **铁律降回设计**——升上去 / 钻下去之后必须落回"页面上该出现什么、强调什么、隐藏什么、默认什么"，只升不降判不合格。内置产品 UI 5 层问法（信息 / 任务 / 判断 / 管理 / 经营）。`references/词表与句式.md` 含禁用词表 / 经营词库 / "从 A 到 B"句式 / 媒体标题生成。**`/pmai-design` 接线**（轻量、走 escape-hatch、不新增强制门）：段① push 深想触及"定位 / 哪张账 / 这前提成不成立"或 PM 说"帮我深想 / 拔高"时调 meta；段② 页面定位掰不清时可调 UI 5 层问法。已登记进 `bin/pmai-doctor` EXPECTED_SKILLS。消费仓 `pmai upgrade` 后即获 `/pmai-meta`。

- `feat(skills)`: **`/pmai-humanize` 新增「视频 / 口播 / 传播文案」语气目标 + 强化"绕弯"病种**。PM 反馈 AI 写东西爱"绕"——靠"不是 X，而是 Y""不止 A，更是 B"先否定再翻转的句式撑场面；写文档里只算 AI 味，放进视频脚本里就是硬伤，传播必须**直给、简短精炼**。改动：① `SKILL.md` 语气目标加第三档「视频 / 口播 / 传播文案 → 直给、简短精炼」，PM 说明这是传播文案时切换；② `references/patterns.md` 把 `否定排比` 行升级为「绕弯 / 否定排比」并点出本质是兜圈子，改法为整句删否定前半、只留结论；③ AI 味段加一条视频/口播硬约束 callout。纯扫描清单与语气目标扩充，不动 skill 行为。

- `refactor(bin+skills+docs)`: **移除 `--local` 项目级安装模式——收敛为纯全局分发（学 gstack 模型）**。消费仓试用暴露根因：`pmai install --local <dir>` 往项目 `.claude/skills/` 拷 skill 实体副本，而 Claude Code **同时加载全局 `~/.claude/skills/` 和项目 `.claude/skills/` 且不按名去重**——两处并存时每个 `/pmai-*` 命令在补全菜单里翻倍，且项目副本不跟随 `pmai upgrade`、越用越陈旧（消费仓 ExampleAgentProject 实测：项目副本停在重构前、还带早删掉的 `pmai-new-req`/`pmai-task-*`）。对照 gstack：它把「命令」和「项目数据」彻底分家——skill 永远只装全局一处，项目里只放非 skill 的 `.gstack/` 配置，所以根本不存在全局/本地打架。**改法（同构 gstack）**：① `bin/pmai-install` 删 `--local` 分支，纯全局（clone `~/.pmai/` + symlink）；② `bin/pmai-upgrade` 删 `--local` 重克隆覆盖整段 + `local_rollback`；③ `bin/pmai`、`install.sh`、`bin/pmai-status` 去掉 `--local` help/示例/占位段；④ `skills/pmai-upgrade/SKILL.md` 去掉全部双模式检测，纯全局；⑤ README / CLAUDE 同步：分发形态、安装模式表、团队仓节全部改为「仅全局」+ 迁移说明。**保留** `pmai uninstall --local <dir>` 作遗留副本清理/迁移入口（不是 footgun，是清场工具）。消费仓需要的 `hooks/` + `.claude/settings.json` 仍单独放项目里（不是 skill，不会重复）。测试 278/0 全绿（无测试依赖 `--local`）。

- `docs(skills)`: **17 个 skill 的 `description` frontmatter 统一重写——菜单门面去黑话、收敛为专业产品语气**。PM 反馈 `/pmai` 自动补全菜单里的说明太长、夹内部黑话（`原 close-work 演进` / `escape-hatch` / `checks-diff 引擎` / `GSD 同构` / 章节号 / `worktree`/`merge 回 main` 等），第一句抓不到「干嘛用」。重写原则：① 第一句为大白话「干嘛用 + 何时用」做菜单门面；② 删内部代号 / 演进备注 / 章节号，工程术语换产品说法（隔离环境 / 合回主线）；③ 保留各 skill 原有触发词（统一成「触发词：…」行），维持模型自动触发不退化。涉 build / cancel / close / codebase-audit / deposit / design / humanize / init-project / mirror-site / mockup / pmai-upgrade / prd-writing / publish-to-lark / quick-fix / skill-improve / status / direction 全部 SKILL.md frontmatter；**纯文案，不动任何 skill 行为**。消费仓 `pmai upgrade` 后菜单说明即更新。

- `feat(skills)`: **新增 `/pmai-humanize`（说人话 / 打磨文字）——通用文字纠错 skill**。治 PM 关心的四样：啰嗦 / AI 味 / 黑话 / 不说人话；对任意 markdown 文档都能跑，不限规格。借社区成熟 skill 的**结构**（blader/humanizer 的多遍过 + 二次自审 + 保嗓音、conorbronsdon/avoid-ai-writing 的三模式 + 词表分级 + 实用性测试），但**用中文 pattern**（社区那套是英文 AI 腔，套不上中文文档）——pattern 目录与 prd-writing 禁用清单 / §3.12 工程黑话词典同源。要点：① 三模式（标注 / 改写 / 就地改）；② 多遍过 + 二次自审（防"自己看不出自己的腔"）；③ **保嗓音红线**——平实即正确，不造金句 / 不强行口语 / 不假亲切（防把重型 AI 味改成亲切 AI 味这种反向 slop）；④ **可选 codex 冷读挑刺**——有 codex 环境才启用（`command -v codex` 检测，没有静默跳过），用独立模型揪残留 AI 味 + 原意有没有被改 + 事实有没有丢 + 有没有过度润色，codex 要求加文采则按平实挡回。prd-writing 的打磨文字收口步（S5）可调它当统一引擎。已登记进 `bin/pmai-doctor` EXPECTED_SKILLS（test-doctor-skills 7/7 过）。

- `refactor(skills)`: **写作体系并版——从"两套风格(spec 大白话 / PRD 重型)"塌成"一套语体 + 章节菜单 + 功能需求按类"**。PM 拍板：不需要分两套风格那种程度，所有文档(spec 和 PRD)统一走**简要易懂**一套语体；区别只在**勾了哪些章节块**(必写/可选菜单)和**功能需求那一节按功能模块类别选组织方式**。改动：① `writing-rules.md` 头部把"L1–L6 必守 + 适用范围两套风格"换成"语体简要易懂 6 条 + 通用卫生(8 类禁用 + 术语锁定 + 引号)"，**原 L1–L5 重型指纹降为"可选讲清楚工具(按需用不强加)"**，L6 术语锁定升入通用卫生；补"收词标准"+ 单个 `×÷` 算式符号可留(写手实测暴露的歧义)；② `few-shots.md` 下半部万智 PRD 样例改标"仅看章节结构、语言仍走简要易懂、别学其重型语气"；③ `info-design.md` 第四块「两类产物两套风格」改写为一套语体模型；④ SKILL.md 写作规则指针 + 质检清单 14–18(原 L1–L5)标为可选工具检查。**A/B 验证**(旧版 4 文件 1471 行 vs 新版单份指引)：风格打平(都干净大白话)，但新版"AI 用得清楚"明显更好——同一份输入旧版烧 ~92.5k token/7 次工具、新版 ~36k/3 次，旧版写手报"单看 writing-rules 会被带偏成 PRD 腔、要多处对照才敢下笔"。旧版框法作为本 commit diff 留底可回滚。

- `fix(skills)`: **prd-writing 模块规格模式补大白话风格锚点——根治 spec 写成白皮书腔**。PM 反馈 AI 出的模块 `spec.md`（如客户侧 ROI）语言偏重、要手工逐句改回大白话。根因：`few-shots.md` 486 行全是重型真系统 PRD 样例（万智平台），**一个大白话模块 spec 实例都没有**——金标准待办 spec 只在 prose 里点名、从没作为 few-shot 给模型看，模型写模块 spec 时只能锚定重型样例。修法（都在 prd-writing 成文引擎，design 路径走它自动受益）：① `references/few-shots.md` 顶部新增「大白话模块 spec 金标准」节——**领域/类无关的风格卡 6 条** + 待办实例（标注"学讲法不学业务"）+ 用 ROI 真实败笔做的**语体转换反例表**；下半部重型 PRD 样例改标"仅 PRD 模式用"。② `SKILL.md` S4 语言关先锚定金标准再守禁用清单（方法论/算法类公式以纯文本保留、去符号堆砌）；S5 加**交付前机械关口**（grep 版本叙事/路径/中英混杂/数学装饰符）+ 冷读语体检查。③ Few-shots 指针按模式分流。**A/B 实测验证可迁移**：同输入、唯一变量=风格卡是否在场，B 臂在两个 few-shot 未覆盖的需求类（纯算法、多对象管理页）+ 两个全新业务域上都产出大白话（加粗 25→11、22→5），证明靠可迁移风格卡起作用、非背业务词。

- `fix(skills+scripts+hooks)`: **全仓 review 修复——gstack skill 前缀误伤 + 飞书参数迁移补记 + hook/兜底加固**——① **去掉误套在 gstack skill 上的 `pmai-` 前缀**（来自批量改名误伤）：`/design-review`、`/design-shotgun`、`/design-consultation` 回归 gstack 裸名，涉 `build` / `mockup` / `design` / `mirror-site` / `codebase-audit` / `init-project` SKILL + `_shared/checks-spec.md` + `CLAUDE.md` review 清单；② **修正本仓脚本名引用**：`build/SKILL.md` 两处可执行命令 `pmai-build-audits.py` → 真实文件名 `build-audits.py`（否则 PM 跑 build 步骤 6 `No such file`）；③ **补记飞书发布参数契约变更**：`scripts/_lib/lark_adapter.py` 的 lark-cli 调用从 `--markdown`/`--mode` 改为 `--content --doc-format markdown`/`--command`（消费仓 sync 时据此调整飞书发布）；④ **两个 doc/jargon hook 的 `-a` 检测补 `--all` 长形式**（`git commit --all` 原先逃过 CHANGELOG/黑话检查）；⑤ **`pmai-upgrade` 加 `timeout` 兜底 shim**（stock macOS 无 GNU timeout 时退化为 gtimeout / 直接执行，避免误触升级失败分支）；⑥ 清理 `_shared/pm-view` caller 清单里已删除的 `next`。回归测试全绿（基线见 RUNTIME.md）。

- `fix(dx)`: **补齐 devex-review 后的开发者入口缺口**——新增 `scripts/migrate-reqs-to-modules.py` 兼容守门脚本，解决历史 CHANGELOG 指向该脚本但当前仓缺文件的 dead end；脚本支持 `--dry-run` inventory，`--apply` 明确拒绝不安全自动迁移。`bin/pmai status` / `doctor` 输出 `CLI source` + `Status/Audit target`，避免 repo-local `bash bin/pmai ...` 和 installed `~/.pmai/bin/pmai ...` 混淆。新增 `CONTRIBUTING.md` + GitHub bug issue template，README 增加开发者自检 / 反馈入口。顺手清理 `tests/run-all.sh` 中两个绿测噪音（BSD `head -n -1`、空 grep alternation）。

- `fix(bin+docs)`: **安装暴露入口按当前 skills/ 全等同步**——`pmai install` 全局安装前清理旧 PMAI symlink，避免删掉的 `/pmai-new-req`、`/pmai-next`、`/pmai-task-*` 继续出现在 Claude Code；`pmai upgrade --local` 去掉硬编码 23 个 skill 阈值，改成等于当前 `skills/`（除 `_shared`）；`pmai doctor` / `pmai status` 支持 `--help`，并检测 `~/.claude/skills/pmai-*` 与当前 `~/.pmai/skills` 的 stale/missing drift。README / CLAUDE 同步移除 `PROJECT.md`、`ROADMAP.md`、`measure-tthw.sh`、固定 skill 数等旧 quick start 残留。

- `fix(skills)`: **codex 审 prd-writing 修复迁移漂移（lifecycle 漏扫该 skill）**——codex 深审 `skills/prd-writing/` 后逐条核验修：① **模板写死旧七阶段**：`req-prd.md.tmpl` 头部 + §六注释把 PRD 描述成 "stage 3 产出 / stage 3 冻结 / close 反向对齐 as-built"，改写为 "沉淀一步按需反向合成"（去 stage 号，对齐 `MAX_STAGE=4` 沉淀模型）；② **读旧单文件模块路径**：SKILL 输入表 / Required Inputs / 步骤 1.5 多处 `docs/modules/<m>.md`（含 X/Y/Z.md）→ `docs/modules/<模块>/spec.md`（对齐 `record-routing.md`）；③ **standalone 三分支没真分流**：步骤 3 生成 / 3.5 lint 硬编码 `$ACTIVE_REQ_DIR/prd.md` → 改 `$PRD_PATH` 按 mode 解析（独立 PRD 用 PM 指定路径）；④ **模板引已删 `analysis.md` 来源** → `brief.md + 范围清单决策页`；⑤ **模板过不了本仓自己的 prd lint**（12 处中文方角引号）→ 全改 ASCII 引号，lint 通过；⑥ **功能表 6 列 vs PM-VIEW-RULES 4 列**：默认表对齐 §五 4 列（二级/三级/使用角色/需求描述，一级功能进 §6.X 标题），优先级列降为可选；⑦ **few-shots 正例违反自身写作规则**（V2.3 迭代语言 / 「」/ 视觉弱化 / 账本 / remove）→ 修正正例措辞；⑧ **维护指令指向非权威文件** → 改指 `_shared/pm-view/writing-rules.md`（权威）+ 脚本黑名单。**未动**：附件落点（耦合 deferred 批 6 `docs/inputs/`，helper 仍 req-local，留批 6 一并迁）。回归测试全绿（基线见 RUNTIME.md）。

- `fix(scripts+skills)`: **codex 整体审计修复 3 个 P1（lifecycle 迁移遗留）**——codex 审 main 现状揪出，逐条核验真实后修：① **banner 全崩**：`status-view.py` `render_banner_only` 读 `req_view["dir"]`，但状态层返回 key 是 `req_dir` → 有 active req 时 `KeyError`（该行在 try 外不兜底），消费仓 session 播报 + 每个 skill 横幅全挂。一字修 key。② **req 编号会撞号**：`req-num-resolver.sh` 编号源只扫旧 `requirements/active|closed` + `req-*` 分支，漏新真相源 `docs/modules/*/.req-meta.json`；close 方案 A 又 `git rm .req-meta` + 删分支 → closed req 磁盘+分支零留痕 → 下一个 req 复用同号撞历史。编号源补扫 `docs/modules`（`.req-meta.json` 的 `id` 字段 + `req-NNN-*` 目录名兜底 close 后），保留旧目录扫描向后兼容老仓。③ **new-req commit 失败**：`new-req/SKILL.md` 步骤 4D 硬 `git add "$REQ_REL/attachments"`，但迁移后附件不再进模块文件夹（批 6 才落地 `docs/inputs/`），无附件时 pathspec fatal 中断整个 commit → 改成存在才 add。回归测试：banner-label T5b（实跑 `--banner-only` 防 KeyError，补 T5 只静态 grep 的覆盖缺口）+ req-num-resolver 3 例（模块 active / close 后仅剩目录 / 模块改语义名靠 id 命中）。回归测试全绿、新增覆盖用例（基线见 RUNTIME.md）。

- `feat(skills+scripts)`: **mock → mockup 改名 + 接入 AI 出图 + 看版重设计**。① skill `mock`→`mockup`（命令 `/pmai-mock`→`/pmai-mockup`，frontmatter `pmai-mock`→`pmai-mockup`），同步 `design`/`info-design`/`dormant-skills` 等引用 + `bin/pmai-doctor` EXPECTED_SKILLS；② 新增 `scripts/gen-mockup-image.sh`——用 codex 内置 image_gen 出 UI 设计稿图（钉 codex **0.135.0**，0.141 无头出图回归不可用；走 ChatGPT 订阅免 API key；脚本自己 diff `generated_images` 取新增图复制，天然验真防拷旧图冒充）；③ `scripts/gen-mock-board.py` 重设计成**单页比稿画廊**（各版画面内联铺一页并排比：图片嵌缩略图、HTML 嵌缩放预览，点开看大图），mockup skill 工作流支持图片 / HTML 两路 + 让 PM 选这轮出几版（借 design-shotgun）。**消费仓需重跑 `pmai upgrade`**：`/pmai-mock` 失效换 `/pmai-mockup`；图片路需本机装 codex（npx 自动拉 0.135.0）。目录名后续统一为 `mockups/`，脚本名 `gen-mock-board.py` 暂保留。

- `fix(skills)`: **design skill codex 第二视角审核修复 3 项**（PM 让 codex 审 /design 后，逐条核验真实性再修）：① `writing-rules.md` 引用路径前缀统一——design / info-design 三处 `prd-writing/...` → `skills/prd-writing/...`，防 AI 按仓库根解析扑空；② 探索段 escape-hatch 产物分档（`req-questioning.md`）：放行档不写 discussion 第一节、仅 push 档"现状切片 + 至少一条值得商榷"必含，消除"必含 vs 按需"自相矛盾（防探索段退回每次必审、抵消 escape-hatch 低疲劳目标）；③ spec 冷读自检澄清用通用 subagent（非只审探索段 discussion 第一节的 `analysis-reviewer`），消除 orphaned handoff。

- `refactor(skills+bin)`: **skill 清单收敛——合并 align-to-live + scrape-prototype → `mirror-site`，project-solution 更名 `direction`**（PM 拍板：两个 brownfield diff 轴流程 90% 同构合一；project-solution 名实不符、定位收窄）。**消费仓需重跑 `pmai install` / `upgrade`**：旧 `/pmai-align-to-live` `/pmai-scrape-prototype` `/pmai-project-solution` 命令失效，分别换 `/pmai-mirror-site`（mode=rebuild / align）、`/pmai-direction`。
  - **mirror-site**：align（对齐自己线上·改存量）+ scrape（照外部站重建·建增量）合一个 skill，用 mode 区分参照来源，共用 /browse 爬 + checks-diff 引擎 + Plan→批→Execute。
  - **direction**（原 project-solution）：定位明确为"项目跑起来后回头校准方向"，只处理方向重定 / 路线规划，与首次起步 / 首次接入（init-project / codebase-audit 内部子流程）划清边界；同步引用（skill / _shared / scripts 提示文本 / templates / docs），**保留历史暂存文件名 `.project-solution-open-questions.md` 不动**（init-project / codebase-audit / direction 共用）。
  - 连带：`pmai-doctor` EXPECTED_SKILLS 同步（`tests/test-doctor-skills.sh` 全等校验护住）、`new-req` brownfield 建议、`dormant-skills.md` 清单更新。

- `feat(skills+scripts+agents)`: **工作方法论纠错实施（6 条开放问题拍板后 A-D 组）**——纠正 reshape "砍仪式补方法"里"补进来的方法本身仍是信息呈现视角 + 砍掉探索整段"的浅设计（设计源 `docs/设计/工作方法论与工作流-总纲.md`，§0 同构错 6 处）。**消费仓影响**（需重跑 `pmai install` / `upgrade`）：
  - **A 立对抗三问强制门**：新增 `skills/_shared/anti-cut-check.md`（减法决策当场答"丢了什么 / 对所有类型成立吗 / 是不是把内核当仪式砍了"+ 对称判别尺、三行自答落 decisions）；接入 dormant-skills 新增条目 + close 减法类沉淀。配套：改造方案 §0 解锁"不可反向修改"元前提锁。
  - **B 真相源修复**：① 理路拆家——撤销"决策收家（折叠 `docs/decisions/` 进 PRODUCT-RULES、3 家减 2）"，恢复 3 个正交的家（理路→`docs/decisions/` 冻结 / 跨模块规则→`PRODUCT-RULES` / 单模块→模块 `decisions.md`），`record-routing.md` + `close/SKILL.md` 反转、删"遇冲突以本 skill 为准"例外、close picker 恢复"冻结成项目理路"第 4 选项；② `build-audits.py` 锚点参数化（`--range-list`/`--audit-dir`/`--label`，敲死"实施时择一"，向后兼容 task-* 回退默认）。
  - **C `/design` 三段式重构**：①探索（新增·补回 reshape 砍掉的整段）→②设计（按需求类型选方法）→③写规格。**删 `req-analysis` skill**、诊断内核搬进 `skills/_shared/req-questioning.md`（office-hours 式对话诊断 + escape-hatch 默认放行 + 闻味触发清单 + 砍外部 demand 三问）；`info-design.md` 删"5 问对任何需求成立"、拆成"真通用内核 3 条 + 七类开放分类选方法"、§八四类补全成七类、禁用清单收归单一真相源；`design/SKILL.md` 重写三段式 + 记忆分档加载 + 进场侧读 TODO / 按需理路；`analysis-reviewer` agent 改挂探索段评审 `discussion.md` 第一节；清 req-analysis 全部残留引用。
  - **D worktree/close 收口**：build 步骤 5 加 `pnpm install`（worktree 复用 store）+ 端口探测错开（并行 build）；close-req.sh cwd 护栏文案软化；`close/SKILL.md` 入口判断改"按本需求开没开 worktree 判（不看 cwd）"支持主仓会话远程操作 worktree。
  - 测试基线 **601/0 全绿**（新增 build-audits 2 个 override 用例；close / stage-source / attachments 测试随改动对齐）。

- `feat(scripts+tests)`: **lifecycle 迁移批 0-4——取消 `requirements/active|closed/` 树，req 状态真相源迁 `docs/modules/<模块>/.req-meta.json`（方案 A·清模块 .req-meta）**（设计源 `docs/设计/lifecycle迁移计划.md`）。**消费仓影响**：close/cancel 语义反转——不再把 req 目录 `git mv` 到 `requirements/closed/`、不再留 `status=closed/cancelled` 占位；收尾 = 清掉模块 `.req-meta.json`（`git rm`），模块三件套（`docs/modules/<模块>/` spec/decisions/discussion）作为长期真相源留场。**消费仓需重跑 `pmai install` / `pmai upgrade` 拉新机器**；在飞 req 迁移走 `scripts/migrate-reqs-to-modules.py --dry-run`（PM 拍后 `--apply`）。
  - **`close-req.sh` 重写**：close = 清模块 `.req-meta`；**有 worktree+分支** → 在 req 分支清 + commit → merge 回 main（ancestor 验证 + 失败回滚 I-CR9）；**无 worktree/无分支**（讨论·小改直接在 main 改的）→ 直接 main 清 `.req-meta` 跳 merge。stage 门对齐 stage 4（沉淀=MAX_STAGE）；cwd-in-worktree / 无关脏文件防护保留（防护范围改按模块路径）。
  - **`cancel-req.sh` 重写**：cancel = 在 main 清模块 `.req-meta`（不 merge），task/req worktree 推迟 cleanup-pending 兜底清；main 污染防护按模块路径。
  - **`_lib/symlink-prd.sh` + `bin/pmai-sync-prds`**：PRD 收口源从 `requirements/closed/<req>/prd.md` 改 `docs/modules/<模块>/prd.md`；sync-prds 扫 `docs/modules/*`（无 `.req-meta` 或 status=closed → closed 类；cancelled → 废弃；active → 跳过）。
  - **`check-status-direct-edit.py`（pre-commit）+ `quick-fix.sh`**：task 状态直改拦截 + active-req warn + redline 路径补 `docs/modules/*` 真相源（旧 `requirements/*` 保留 dormant 兼容）。
  - **`check-branch.sh` GATE 1/2/3（批 1/2 已落）**：main 写保护放宽 `docs/**` 全放行（`prototype/` 仍拒绝、stage 字段仍走 req-transition）；GATE 路径迁 `docs/modules/*`。
  - **INVARIANTS 对齐**：I-CR1/3/4/5/8 + I-CA4 + I-CB3/5/6 + I-DC1 + I-RT4 改语义；**新增 I-MOD1**（模块工作状态真相源 = `docs/modules/<模块>/.req-meta.json`、走 `_lib.state` helper）；task/exec 系列标 🟡dormant（代码保留·测试仍跑）。
  - 测试基线 **599/0 全绿**（批 0-2 后 588→599；批 3/4 零净回归）。

- `docs(设计+skills)`: **瘦身改造 v2 起步——消费仓文档结构重定义 + 沉淀分流对齐新布局**（设计源 `docs/设计/吸收ExampleAgentProject设计方法-改造方案.md` §3/§5/§6）。方向：砍框架过度设计（仪式）、借 ExampleAgentProject 工作模式（模块三件套 / design-card / spec-polish / mock）、补真实缺口（跨 req 决策+术语记忆 / 规格质量 / worktree 隔离）。**本批先落文档结构定义 + 沉淀路由对齐；lifecycle 迁移（取消 requirements/ 树、瘦 close 机器）单独走、必跑测试。**
  - **新增 `docs/设计/消费仓文档结构.md`**：新布局权威定义——`docs/` 一棵树装下所有真相源（项目级 `PRODUCT/PRODUCT-STATE/PRODUCT-RULES/DESIGN/TODO` + 模块级 `docs/modules/<模块>/` 三件套 `discussion.md`/`decisions.md`/`spec.md` + `.req-meta` 工作状态 + 附件 `docs/inputs/<类别>/` 自动归类）；**取消 `requirements/active|closed/` 整棵树**；**决策从 3 个家减到 2 个**（模块 `decisions.md` + 项目 `PRODUCT-RULES`，`docs/decisions/` 折进 PRODUCT-RULES）；worktree 统一挂 `.worktrees/<分支>/`；模块文件夹取代旧 `docs/modules/<m>.md` 单文件。含「放什么进哪」路由表 + 「自动归位」行为定义（文档归位 / 附件归类 / 决策回写 / 术语回写）+ 留给 lifecycle 迁移 agent 的 6 个交接接口。
  - **`skills/_shared/record-routing.md` 对齐新布局**：四类分流扩成六类——① 耐久事实（落点加模块 `spec.md`）、② 决策与理路（2 个家：跨模块→`PRODUCT-RULES` / 单模块→模块 `decisions.md`，吸收原 `docs/decisions/`）、③ 遗留→TODO、④ 探索变体→mockups、**⑤ 跨 req 决策回写**（治"跨 req 没记忆"）、**⑥ 术语回写**→`PRODUCT.md` 业务术语表；新增「附件自动归类」节（按类型落 `docs/inputs/<类别>/`、去 per-req 作用域 + stage_prefix、**保留** denylist + 50MB cap + untrusted 边界）；开火点更新为 `/close`（原 close-req）+ `/pmai-record`（dormant 保留）。
  - **接口留给 lifecycle 迁移 agent**：requirements/ 取消（req-plan/brief/prd/attachments/.req-meta 按路由表迁走 + 瘦 `close-req.sh`/`req-transition`/I-CR·I-RT）、`.req-meta` 从 per-req `.req-meta.json` 搬到 per-模块 `docs/modules/<模块>/.req-meta`、附件 helper rewire（去 `req_dir`/`stage_prefix` 改 `inputs/<类别>/`、保留护栏）、`docs/decisions/` 折进 PRODUCT-RULES、`docs/modules/<m>.md`→文件夹三件套、文档地图 + 防腐铁律对齐。

### PMAI 重构落地（office-hours 收敛）—— 进行中

- `feat(skills+scripts+templates)`: **分档运行 + 每档沉淀 + mock 变体治理 + 项目决策记录**（统一三份设计落地：`分档运行与沉淀层` / `文档治理与知识棘轮` / `项目奠基决策记录`）。解 PM 四痛：①轻档（main 直接改）漏沉淀 ②脊柱入口看不到实存文档 ③成熟决策困在讨论稿 ④mock 探索变体找不回。**消费仓需重跑 `pmai install` / `pmai upgrade` 拉新 skill（`/pmai-record`）+ 重 init 的项目才有 `docs/decisions/` + `mockups/` 脚手架；存量项目这两个目录首次用到时由 skill / PM 手建。**
  - **新增 `/pmai-record`（轻档轻沉淀）**：main 上聊定 / 改完后把成果按四类归位（现状→PRODUCT-STATE / 理路→决策记录 / 遗留→TODO / 探索变体→mockups 看版），两道闸（收敛点 + 有耐久产出才提）+ 切两挡（纯静默档静默写 / 需审档总审 diff）+ AI 单独 `沉淀:` commit 不卷 WIP。skill 数 22 → 23。
  - **分档运行模型**（`CLAUDE.md.tmpl`）：轻（main 直接改 + `/pmai-record`）/ 中（轻 req 直建 + close-req）/ 重（完整 req + close-req）三档，每档一个沉淀开火点；+ AI 主动提议沉淀的行为规则。
  - **四类分流单一真相源** `skills/_shared/record-routing.md`（close-req 中/重档 + deposit 轻档共用）；close-req 步骤 2/2.5 加理路类识别（AskUser「冻结进决策记录」第 4 选项）+「推下个需求」自动入 TODO（F-G3 单一真相源、close-report 只渲染指针）。
  - **项目决策记录（冻结档）**：`templates/decision-record.md.tmpl` + `skills/_shared/decision-record.md`（共享冻结参考）；触发点 project-solution 步骤 8.5 / init-project C-6.5 / close-req 2.5；落 `docs/decisions/<日期>-<slug>.md`（带日期、写一次不维护，不在防腐铁律内）。new-req 起步扫 `docs/decisions/` 列已有记录、范围触及理路域则读回（F-G1 主动触发）。
  - **mock 变体治理子系统**：`scripts/gen-mock-board.py`（manifest 真相源 → 生成看版 `index.html`）+ `templates/mockups-{manifest.json,README.md}.tmpl` + `mockups/` 脚手架；new-req 视觉变体探存进 `mockups/` 不再挑定即弃；退役标记不删。
  - **文档地图 + 脊柱两层读取模型**：`templates/文档地图.md`（框架全局，CLAUDE 放 `$PMAI_HOME` 指针）；PRODUCT-STATE = 必读核心、PRODUCT/DESIGN/RULES/modules/decisions/主原型 = 索引展开层。
  - **防腐铁律扩**：PRODUCT-STATE 现状写口从 1 个（close-req）→ 2 个 sanctioned（+ `/pmai-record`），仍互斥收敛。`check-branch.sh` GATE 3 新增：`mockups/*` + `docs/decisions/*` main 无条件可写（探索草稿 / 冻结档豁免）；`docs/PRODUCT-STATE/RULES/TODO/modules` 经 `.runs/deposit-in-progress` marker 门控放行（blast radius 限定沉淀落点）。
  - **索引漂移检测** `scripts/check-state-index-drift.py`（new-req 起步跑，advisory）：报 docs/ 顶层实存但 PRODUCT-STATE 索引漏挂的文档。
  - 测试：+5 GATE 3 沉淀分档用例 + test-mock-board（7）进 run-all；基线 **588/0 全绿**。

- `fix(skills+scripts)`: **stage 编号清理 + banner 去号**（`stage编号清理与banner去号` 设计落地）：runtime AI 读的 prose 里残留的旧 7-stage 编号（`stage 6` 等）清成阶段名（范围确认 / build / 复审 / 沉淀），治 AI 把概念号当 stage 号推过头；banner 去 `Stage N/T` 只显阶段名；input-flow §9 加六步↔内部 stage 唯一映射表；新 lint hook `hooks/check-stage-number-jargon.cjs` 拦回潮。quick-fix 产物链旧编号 DEFER（独立 blast radius）。

- `refactor(skills+scripts+templates)`: **项目底座文件 `docs/PROJECT.md` → `docs/PRODUCT.md`**（与 PRODUCT-STATE.md / PRODUCT-RULES.md 三兄弟统一命名）。消费仓试用反馈：`PROJECT.md` 标题写「项目背景」、装的却是产品定位/用户/术语，跟两个 PRODUCT 兄弟不一条心，名实不符。改名采**最小一致**范围（PM 拍板）：
  - **文件名 + 全部引用**：`templates/PROJECT.md.tmpl → PRODUCT.md.tmpl`（H1「# 项目背景」→「# 产品背景」）；29 个框架文件里的 `docs/PROJECT.md` 路径、按钮文案「创建 PROJECT.md」→「创建 PRODUCT.md」、裸词文件简称全改。脚本层硬路径同步：`check-project-sections.py` / `status-view.py` / `init-project.sh` cp case / `check-docs-toplevel.py` 白名单 / `check-branch.sh` 写保护 / `_lib/term-detector.py`。
  - **migrate 脚本升级**：`migrate-context-to-project.py` 扩成双跳（CONTEXT.md **或** PROJECT.md → PRODUCT.md 一步到位），老消费仓升级跑一次即可平滑迁移。
  - **顺手对齐 5/6 节**：脚本 `check-project-sections.py` 一直是 5 节为准（项目名称/产品定位/用户画像/技术栈/业务术语表），SKILL 里误写「6 节」的（project-solution / new-req / init-project）改回 5 节。
  - **不动**（最小一致边界）：skill 名 `pmai-project-solution` / 脚本名 `check-project-sections.py` / 共享文件 `project-questioning.md` / 暂存文件 `.project-solution-open-questions.md`（PM 不直接看、改名 blast radius 远超收益）；模板 5 个二级节名（脚本数据键）；真「项目/工作层级」措辞（项目方向/项目级 vs req 级，活动概念非文件内容）。
  - 测试 fixture 同步（fixture.sh / test-narrative-mode / test-docs-toplevel-guard / test-docs-archive-convention / test-no-duplicate-questioning 锚点）。基线 573/0 全绿。

- `fix(skills+scripts+templates)`: **ROADMAP → TODO 待办池（AI 不反推填充 / 不排序）+ codebase-audit 兜底建 PRODUCT-STATE**（消费仓试用反馈）。基线 573/0 全绿。
  - **ROADMAP.md → TODO.md，去「路线图」语义**：PM 反馈 brownfield 方向讨论时 AI 从代码 / 竞品反推出一串 req 还替 PM 排好顺序，是 PM 没要的。根因：旧 ROADMAP 设计成「历史 + 未来一张表 / 唯一规划视图 / 排序数字小先做」，还指示 AI「先扫 `requirements/closed/` 反推 done 行」「替 PM 排 planned 队列」。改法：`templates/ROADMAP.md.tmpl` → `templates/TODO.md.tmpl`，改成**无序待办池**——只记 PM 提过 / 讨论过想做的，状态 todo/doing/done，**去掉「排序」列**，AI **不从代码 / 竞品 / `requirements/closed/` 反推填充**。PM 要起需求时 AI 提醒「池里有这些」让 PM 挑，不替 PM 定「下一个该做 X」。真相源 `_shared/project-questioning.md` §5.2/§5.3 重写，调用方 project-solution（A/B/C/D 场景）/ codebase-audit step 4 / init-project C 步全部跟改；`init-project.sh` cp case、`status-view.py` 存在性检查、`check-docs-toplevel.py` 白名单、`CLAUDE.md.tmpl` 三处约定、4 个测试 fixture 连带改名。`test-roadmap-guidance.sh` → `test-todo-guidance.sh` 重写成反向断言（断「无序待办池 / todo-doing-done / AI 不反推填充」，防回归）。**机器零依赖**：除 status-view 查存在性外无脚本读 ROADMAP 内容。
  - **codebase-audit 兜底建 PRODUCT-STATE.md**：greenfield 的 `init-project.sh` 会铺 PRODUCT-STATE 模板，但 brownfield 走 codebase-audit 从不建它 → 消费仓缺这个「产品现状层」hub，下游 `new-req` 范围确认（强制读它）退化成白纸起步。照 step 3.5.5（DESIGN inventory 兜底）同款无条件模式，新增 **step 3.5.7：PRODUCT-STATE.md 兜底**——HAS_FILE 探测 → 缺则建骨架 + 从现状档反推填「当前功能 / 主原型现状 / 实现深度」三段（产品现状 = 已发生事实，反推是对的；产品定位一句话留空、step 4 定方向后回填）。含**防腐豁免**措辞：首次 bootstrap ≠ 违反「只在 close-req 更新」铁律，由顶部状态行标注草稿态区分。

- `fix(skills+scripts+templates)`: **brownfield 接入改一气呵成 + 消除「脊柱」黑话 + 中文产物文件名转英文**（消费仓试用反馈三连）。
  - **brownfield 接入不再两段手敲**：`/pmai-codebase-audit` 原本扫完现状档就停下、要 PM 手敲第二个命令 `/pmai-project-solution` 才定方向 —— 与 greenfield `/pmai-init-project`「一个命令含方向讨论」不对称。根因：设计把「留 PM 消化现状档的时间」和「逼 PM 手敲第二命令」绑死，但方向讨论逻辑早已共享在 `_shared/project-questioning.md`（init-project 阶段 C 就内联跑）。改法：codebase-audit step 3 呈交现状档后留**轻停顿**（PM 过目、可离线读），PM 说「继续」→ **step 4 内联跑方向讨论**（@读同款 `project-questioning.md` + 现状档实况，产 `docs/PROJECT.md` + `docs/ROADMAP.md` + Decision gate + atomic commit + ▶ Next Up 引到 `/pmai-new-req`），不交接出去。`project-solution` 保留但场景 D 从「接入必经步」降级为**接入方向讨论被打断的异常恢复入口**；`project-questioning.md` 调用方契约补登记 codebase-audit step 4 为第三调用方。
  - **「脊柱 / 上下文脊柱 / 产品脊柱 / 项目脊柱」→「项目底座」**：PM 看不懂内部黑话「脊柱」。17 个同步资产 70 处统一改「项目底座」，零残留。指代不变（PRODUCT-STATE / PROJECT / DESIGN / PRODUCT-RULES / ROADMAP + prototype/，AI 每次进项目先读、治失忆的根基）。
  - **中文产物文件名转英文**：`docs/代码现状档.md` → `docs/CODEBASE-AUDIT.md`（对齐 PRODUCT-STATE.md / PROJECT.md / DESIGN.md 全大写项目级命名，含 codebase-audit SKILL + 模板 + project-solution + project-questioning 全部引用）。面向 PM 的概念词「代码现状档」保留中文，只改落盘路径。归档目录随后已在本轮 layout 改造中统一为 `docs/archive/`。
  - **补修 init-project 首 commit gate**：`init-project.sh` 已生成 `docs/PRODUCT-STATE.md`，但 `check-docs-toplevel.py` 静态白名单漏了它，导致新项目 / `--allow-existing` brownfield / TTHW smoke 在首 commit 被 pre-commit 拦下；补白名单 + 回归测试。另修开发仓自测被全局旧版污染的问题：`init-project.sh` 框架解析顺序改成显式 `PMAI_HOME` > 脚本所在框架根 > `~/.pmai`，并把解析出的 `FRAMEWORK_DIR` 导出为 `PMAI_HOME` 给首 commit hook；`measure-tthw.sh` 同样走自身框架根脚本。

- `docs(skills+tests)`: **收 task-plan SKILL 三处「产范围清单」误导措辞**（description / When To Use / 「task 是什么」）。根因：task-plan 实际产物是 task 拆分（task 列表 + 执行顺序 + GAP 映射），其模板里**没有「范围清单」节**，但 SKILL 措辞写成「产/细化范围清单」，让它看起来和 new-req 的 `req-plan.md`（范围清单 WHAT + 决策页 WHY）职责重叠；且自称「它产的范围清单是覆盖审计锚点」与真相源 `input-flow.md`（覆盖审计对照 **req-plan** 范围清单，build spike 已实证）冲突。改为「承接 req-plan 范围清单、拆成可验收 task 单元」，明确锚点归 req-plan、本 skill 不另产、不复制。连带修 `test-implementation-design.sh:43` 注释「task-plan 的 req-plan.md」→「new-req 产的 req-plan.md」（req-plan 是 new-req 的产物，非 task-plan）。**纯措辞 + 注释，零功能改动**，test-task-plan 8/8、test-implementation-design 4/4 零回归。

- `fix(scripts+skills+templates)`: **第二轮 gstack-review 修复（四源交叉：手工 + 2 Claude agent + Codex 跨模型）**——验收 `reshape-office-hours` 全工作产出，修一批绿网测不到的完整性缺口。基线 572 → **572 全绿**（断言 1:1 替换、用例数不变）。
  - **prototype/ 改名收尾**（设计 §3「收敛为单一 prototype/ 升一等概念」，复数残留是 blast-radius 漏扫）：`init-project.sh` `mkdir prototypes` → `prototype`（单数，对齐 build-audits / check-branch / 所有 SKILL）；`check-branch.sh` GATE 4 删 `req-*) prototypes/*) deny`（**PM 拍**，对齐 D10：轻 / 文档 task 不 fork、在 req worktree 直接改原型——旧拦截前提「所有原型改动走 task 分支」六步后不成立，且死守复数路径=对真路径 `prototype/*` 永不触发）；`quick-fix` 反向同步表 / `cross-skill.md` / `writing-rules.md` 的 `prototypes/` → `prototype/`。
  - **build-audits 接线缺口**（Codex 抓）：`build-audits.py:_dev_ports` 加 YAML block-list 解析（`pm-workflow.config.yml.tmpl` 默认就是 block list，旧版只认 inline `[...]` → 默认配置解析成空端口、resolve fail-loud）；`task-verify/SKILL.md` 新增步骤 6.5 **自己写** `.pm-workflow/audits/<模块>/behavior.json`（确定性产物；原靠 build 流程事后转换、无确定性生产者 → synthesize 缺它 fail-loud 卡正常 UI task）；`build-audits.py` 加 `_validate_audit_shapes`（畸形 audit 数组 fail-loud 点名哪道、不抛裸 AttributeError）。
  - **bash `$VAR` 紧跟 CJK 全角标点 blast-radius**（前次审只修 `_gate.sh` 一处；实证 macOS bash 3.2 + `set -u` 下崩 exit 127）：`close-req.sh:96` `$REPO_ROOT）` / `task-verify/SKILL.md` `$TASK_WORKTREE（` / `dev-server.sh:71` `$pid：` → `${VAR}`。
  - **`python3 -c` 路径插值代码注入加固**（pre-existing 防御纵深）：`init-project.sh` / `_setup-deps.sh` 端口推导从 `'$path'` 插值改 `sys.argv[1]` 传值（恶意目录名不再越狱执行）。
  - **checks-diff.py JSON 健壮性**：plan 解析失败友好 fail-loud（不抛裸 traceback）；单个畸形 artifact JSON 报 P0 不崩整份报告（`PARSE_ERROR` 哨兵，对齐已有 shape-错误处理）。
  - **README + 模板 + docstring 六步对齐**：`README.md` 两处流程图 + 命令表从 7-stage 多窗口重写为六步单窗口（4 入口 + task 机器降后台）；`task.md.tmpl` 删 SIMP-N carve-out / `implementation-design.md` 死引用 / `prd.md`→`req-plan.md` / 死路径 `pmai-task-plan.md`→`task-plan.md`；`state.py` / `req-transition.py` docstring `/7`·`1-7`·旧 stage 5→6 → 六步；`project-solution` 把 req-stage-gate 当活跃驱动的指针 → `/pmai-next`。

- `feat(scripts+skills)`: **build 三道审脚本级编排落地**（六步落地原余下项）。新增 `scripts/build-audits.py` 把三道审能确定性固化的部分固化（覆盖审计是 agent、视觉门是 gstack skill —— 这两道仍由 task-execute 用 Agent/Skill 工具调起，脚本不当子进程调 LLM）：
  - `resolve <task-file>`：校验输入（范围清单 `req-plan.md` / `prototype/` / `.pm-workflow/config.yml` 的 dev 端口）→ 缺则 **fail-loud**（防对着缺失锚点跑审）；建 `.pm-workflow/audits/<模块>/` 内部审计目录；打印三道 manifest（每道读什么、把规范化结果写哪、dev server 复用约定）。
  - `synthesize <task-file>`：读 `.pm-workflow/audits/<模块>/` 下三道规范化结果（`coverage.json` / `visual.json` / `behavior.json`，统一 schema）→ **校验三道齐全**（漏跑 fail-loud 点出缺的那道，挡住「漏跑一道还往下走 / 各起 dev server / 不合成」）→ 合成一份 `synthesis.md` 给 PM（覆盖 丢了/降级 + 视觉 findings + 行为 pass/fail + 建议改的项）+ stdout 机器 summary（各道计数 + gate=clean|needs-review，门禁仅作给 PM 的建议、不替 PM 拍板）。
  - `task-execute/SKILL.md` 步骤 7.3 接线：开头 `resolve` 校验、各道写规范化 json、7.3d 改调 `synthesize`。回归 `test-build-audits.sh` 7 例（输入缺失 fail-loud / 三道漏跑 fail-loud / clean·needs-review gate / --fail-on-gate 退出码）。基线 565 → **572 全绿**。**剩 build spike 端到端验证**（真 req 上跑 coverage-reviewer/design-review/task-verify 产出 conformant json + 整个 loop）—— 见 TODOS。

- `refactor(scripts+skills+templates)`: **review 残留项按 PM 授权判断后处理**（PM 让 AI 判断 4 个 deferred 项）。基线 579 → **565 全绿**（删 test-speed-mode.sh 14 用例）。
  - **退役 speed mode 子系统**（7-stage 优化，坍缩后驱动 `req-stage-gate` 编排已删 → 残件全死）：删 `scripts/_lib/stage6_summary.py` + `status-view.py --stage6-entry`（import / argparse / handler）+ `tests/test-speed-mode.sh`（出 run-all）+ `task-plan.md.tmpl` 的 per-task「决策类型」列（六步结构决策走 task-plan 步骤 3.5 §二 执行模式门，无 per-task 消费者）。核实：无任何 skill / req-stage-gate / 活测试调用这些（仅 status-view 自引 + 钉装饰列的 test-speed-mode）。`implementation-design.md.tmpl` 已整体 DEPRECATED，其内残留列不单独清。
  - **prototype/README.md 接线**（init 未铺它的修复）：`init-project/SKILL.md` C.5 step 3 改为脚手架（`create-next-app`）**之后**用 `prototype-README.md.tmpl` 覆盖 `prototype/README.md` —— 不在 B 步 init.sh 铺，避免与 create-next-app 非空目录冲突。
  - **close-task ② 视觉基线段定位容错**：DESIGN.md 有两种合法结构（gstack 英文细分段 `## Color` 等 / 模板手填单节 `## 一、视觉基调`），close-task 1.5.3 ② 改为按实际结构定位（gstack 段优先、否则 patch 进 `## 一、视觉基调`、都无则 append），不再只认 gstack 英文段。不强行统一段名（会丢模板的框架专属节）。
  - **deliverables-INDEX = 不改**（判断后确认现状已对）：`CLAUDE.md.tmpl` 产物层已写「目录 / INDEX 不存在就建」= lazy 创建（按需能力不该 init 硬铺空目录）。
  - **build 三道审脚本级接线**：本批先标 TODO，PM 让继续后已落地（见上一条 `build-audits.py`）；剩真 req build spike 端到端验证。

- `fix(scripts)`: **gstack-review 审出的 4 个 P0 修复（六步重构落地缺口，破坏头号特性）**：
  - **外部执行器 dead-on-arrival**（codex / cursor / gemini 启动即崩，根因 pre-existing `_gate.sh`）：`exec-adapters/_gate.sh` 把 framework `scripts/` 路径从 `$MAIN_REPO_ROOT/$HOME/.pmai/scripts`（两个绝对路径相拼 → 翻倍成不存在路径 → 走 `_gate_fail`）改为从 `${BASH_SOURCE[0]}` 解析（同 close-task.sh 的 SCRIPT_DIR，不依赖 PMAI_HOME 导出），并修 `_gate_fail` 里 `$transition_py）`（变量紧跟中文 `）`、`set -u` 下被当 `transition_py<byte>` → unbound 崩溃）→ `${transition_py}`。三个外部 adapter 此前 precheck 必崩、且唯一能抓到它的 `test-executors.sh` 未进 `run-all` 让绿网掩盖——本批修 + 把该套纳入 `run-all` + 补 gemini.sh shim 用例（空数组展开 / 透传 model）。默认 `claude-code` 执行器走 subagent 不经 _gate.sh、不受影响。
  - **沉淀(close-req) 主流程死路**：`close-req.sh` 的 stage 门 `!= "7"`（旧 7-stage）→ `!= "4"`（六步沉淀 = MAX_STAGE；close-req/SKILL.md Phase 1 已 `--to 4`）。原门让任何六步 req 永远关不掉（卡「请先推进到 stage 7」），`test-close-req` / `test-symlink-prd` 用 stage-7 fixture 掩盖了死路 → 同步改 fixture 到 4。
  - **上下文脊柱未被 init 创建**：`init-project.sh` 的 template case 补 `PRODUCT-STATE.md → docs/PRODUCT-STATE.md` / `DESIGN.md → docs/DESIGN.md`（原默认分支 `*) continue` 把这两个新脊柱模板整个跳过 → 下游所有 FORCE READ `docs/PRODUCT-STATE.md` / `docs/DESIGN.md` 读空、治失忆脊柱在新建项目里根本不存在）。
  - **迁移锁死旧 stage-4 active req**：`migrate-reqs-to-6step.py` 加 `new == old` no-op 跳过（不再给旧 stage 1-4 盖假 `migrated_from_7stage` 戳 / 污染 stage_history，等价「只动越界值」）+ 非 int stage 跳过 + 跑完列出所有 **active 且 stage∈{3,4}** 的 req 让 PM 手工确认（旧 prd(3)/design(4) 与新复审(3)/沉淀(4) 同号、脚本无法区分；不做不安全的自动迁移，避免把未完成需求当不可逆完成态）。docstring 改成与代码一致（{5→1,6→2,7→4}，1-4 不动）。
  基线 543 → **576 全绿**（含新纳入 run-all 的 test-executors 30 + migrate 歧义回归用例 + close-req/symlink-prd fixture 改 4）。
- `fix(scripts+skills+templates)`: **gstack-review P1 + P2 全修（六步对齐 + 健壮性）**。基线 576 → **579 全绿**。
  - **P1 脊柱读路径**：`task-plan/SKILL.md` 步骤 0.5 FORCE READ 与 `implementation-design/SKILL.md` Required Inputs 的 `$REPO_ROOT/PRODUCT-STATE.md` / `DESIGN.md` / `PRODUCT-RULES.md` 补 `docs/` 前缀；`close-task/SKILL.md` 步骤 1.5.0 / 1.6.1 的 `$MAIN_REPO_ROOT`（从未定义）→ `$REPO_ROOT`；`prototype-README.md.tmpl` 散文指针补 `docs/`。修前这些 FORCE READ / 视觉规范沉淀静默 no-op。
  - **P1 task-plan.md.tmpl 六步对齐**：输入清单 brief/analysis/prd/implementation-design/prototypes → `req-plan.md` + `docs/PRODUCT-STATE.md` / `docs/DESIGN.md` + `prototype/`；删 stage 5/6/7 编号 → 范围确认阶段产物 + `/pmai-next` 推进；§4.2 GAP 来源 prd §七 + implementation-design SIMP → req-plan 范围清单 + 决策页 D-NN；反模式 A 文档类沉淀 `/pmai-doc-update` → close-req 沉淀进 PRODUCT-STATE/DESIGN；补「每个 task 四字段」（执行深度/PM确认/不做/并行性）。**保留「决策类型」列**（test-speed-mode T4 钉 + speed mode 是否退役是 PM 决策，仅修其中 req-stage-gate / PRD §七§六 死引用）。
  - **P1 多窗口残留**：`task-submit`（不再"切 req 窗口再跑 close-task"）/ `task-spec`（task-confirm 后台 fork、控制权回 /pmai-next 同窗口）/ `task-status`（"新窗口启动" → /pmai-next 同窗口）/ `task.md.tmpl` 状态图入口 全对齐单窗口。（new-req / close-req 的"新窗口 / 两阶段"是 req 级 worktree 边界、合法保留。）
  - **P1 代码安全**：`checks-diff.py` `check.id` 路径穿越防护（allowlist `[A-Za-z0-9._-]`、禁 `..`）；`task-transition.py --discard` 硬编码 `.worktrees/<branch>` → 问 `git worktree list`（认 `PM_AI_WORKTREE_BASE` / 任意位置）回退约定，避免自定义 base 下留孤儿 locked worktree。
  - **P2 健壮性**：`checks-diff.py` 畸形 artifact（非 dict / buttons 非数组）报 P0 不崩整份报告 + 无断言 check 报 P2「无可执行断言」不静默判无差异（回归 3 例）；`create-task-worktree.sh` lock 失败从 `2>/dev/null||true` 改显式告警（并发删除防线缺位不再静默）；`status-view.py` `suggest_next_action` 整体 7-stage → 六步（1 范围确认/2 build/3 复审/4 沉淀，含 `stage==7` 死分支 + 内部 task-confirm/task 窗口旧引用）；`_lib/state.py` 注释「1-7」→「1-MAX_STAGE」；`DESIGN.md.tmpl` 补 `## 共享组件 inventory` 空段（new-req 2B 断言 + close-task ③ patch 依赖它）；`implementation-design.md.tmpl` 加 DEPRECATED 横幅（六步降后台、不产文档；保留决策类型列给 test-speed-mode T3）。
  - **残留（PM 决策 / 结构判断，未动）**：speed mode 子系统整体退役（`--stage6-entry` / `stage6_summary.py` / 决策类型列 / test-speed-mode）—— RUNTIME 明记「不擅自废、PM 拍」；DESIGN.md 视觉基线段 gstack 英文段名 vs 模板中文段名的统一（close-task ② patch 目标）—— 结构决策、与 gstack 集成交织；prototype-README / deliverables-INDEX 是否由 init 铺（涉及 create-next-app 目录冲突 / lazy 创建）。
- `chore(scripts)`: **根目录文档归档清理**（连带 2 个同步脚本的陈旧引用）。`框架同步-SOP.md`（DEPRECATED）→ `docs/归档/废弃/`、`GSD-参考调研.md` → `docs/归档/完成/`、误粘 Cursor 聊天 `1.md` → `docs/归档/废弃/误粘-cursor聊天记录.md`；根目录只留 7 个活真相源。**消费仓影响**：`audit-task-events.py` 的「框架太老」提示从「按 框架同步-SOP.md §4.11 同步到 \<短 hash\>」改成「跑 `pmai upgrade` 同步」（去掉指向已归档 SOP + 短 commit hash 的陈旧引用，更 consumer-actionable）；`status-view.py` 注释去掉 SOP §4.10 引用、改内联「读侧容错」。README/CLAUDE/INDEX/框架分发设计稿 link 同步新路径。
- `feat(skills)`: **§7.A 站点爬 + §7.B 对齐线上 skill 落地**（按需 brownfield 能力，共用 §7.C 引擎；§7.A/B/C 全套完成）。`skills/scrape-prototype`（`/pmai-scrape-prototype`）：gstack `/browse` 爬目标站每页每弹窗 → 派生 checks-spec + 截图 → `prototype/` 栈内**重建近似**（只看不导、非无损拷贝）→ checks-diff 验重建。`skills/align-to-live`（`/pmai-align-to-live`）：把 `prototype/` 对齐**线上真实产品**（第四条 diff 轴），两阶段 **Plan**（爬线上派生 checks → PM 批）→ **Execute**（抓两边 → checks-diff → 改原型），吸收 PM 雏形 `prototype-live-align` 的红线（PM 没批不改原型）。都 @读脊柱 + 单窗口 + checks 由 AI 派生不让 PM 写 JSON + 登录后页面才用 `/setup-browser-cookies`。**按需调**：PM 手动，或 new-req 范围确认里 PM 话里有「照某站做 / 对齐线上」信号时 AI 建议一句（pattern 沉淀、不机械弹）。
- `feat(scripts)`: **§7.C checks-spec 统一引擎**（§7.A/§7.B 的共用底座，吸收自 PM 雏形 `prototype-live-align`）。`scripts/checks-diff.py`：拿 checks-spec（每页 `must_have_text` / `must_check_buttons[disabled]` / `must_cover_states`）+ 抓取产物（reference/local，gstack `/browse` 抓）→ P0/P1/P2 差异报告 + patch TODO。**参照物无关**：覆盖审计（参照=范围清单、无 reference 只查 local must-have）/ 对齐线上 §7.B（参照=线上）/ 站点爬 §7.A（参照=目标站）共用同一引擎。schema 文档 `skills/_shared/checks-spec.md`（checks 由 AI 派生、不让 PM 手写 JSON）；视觉细则归 DESIGN / 工程结构约束、状态覆盖归行为审，引擎只查结构 / 文案 / 按钮态。回归 3 例。基线 **543 全绿**。（§7.C 不独立做 —— 这里作 §7.A/§7.B 引擎落地；两个消费 skill 随后。）
- `feat(scripts)`: **旧 7-stage req 迁移脚本（解除最后一条消费仓 sync 阻塞）**。`scripts/migrate-reqs-to-6step.py` 把旧 req `.req-meta.json:stage` 的越界值（5/6/7 —— 新引擎 `MAX_STAGE=4` 下显示 "?"、transition 校验失效）重映射到六步：旧 1-5 → 1 范围确认 / 6 → 2 build / 7 → 4 沉淀。**只动明显旧 7-stage 的 req**（`stage > 4` 或 `stage_history` 出现过 > 4），幂等 + `--dry-run`，标 `migrated_from_7stage` 溯源。closed 旧 req（多数）→ 4 沉淀=done 干净；in-flight 旧 req 映射后无六步产物、不能直接续跑（脚本提示在旧框架收尾，产物迁移不在范围）。回归测试 4 例。**消费仓升级前跑一次即解越界**——配合 CLAUDE.md.tmpl 重写 + attachments rewire，三条 sync 阻塞全清。基线 **540 全绿**。
- `fix(templates)`: **CLAUDE.md.tmpl 六步重写**（解除第二条消费仓 sync 阻塞）。init 装给消费仓的 CLAUDE.md 模板原本大量 pre-reshape，重写：会话起始 `/pmai-task-status` → `/pmai-next`；**角色定义** 多窗口（主 Orchestrator / 新窗口 Claude / Execution Agent）→ **单窗口**（PM / 驱动 Claude / 独立执行器，PM 在 task 卡 `executor` 指定 claude-code·codex·cursor·gemini）；**入口序列** 旧 7-stage 多窗口 task-spec→confirm→新窗口→submit → **六步 4 入口**（init / new-req / next / task-status，全程一个窗口、机器步骤降后台）；**确认门** stage 3 PRD / stage 4 DESIGN → 范围确认定稿门 / 呈交验收门 / 沉淀；**review 推断** stage 2/3/5/6 → 六步阶段；`prototypes/` → `prototype/`；**文档位置表** prd-stage3 / impl-stage5 → `req-plan` / `PRODUCT-STATE` / 按需 prd。保留测试钉的占位符 + `## 工程结构约束` 段 + docs/归档 / 产物层 / gstack / review 约束 / I-AD5 / I-RV1 等有效段。基线 **536 全绿**。
- `feat(templates)`: **§7.D 产物层（deliverables 通道）落地**。`CLAUDE.md.tmpl` 加「## 产物层」一条通道（**不建插件框架**）：PM 做产品介绍 / PPT / 图片 / 对外文档等产物时——任何产物生成（skill 或临场「在仓库里生成 X」）**第一步 @读脊柱**（`PRODUCT-STATE` → 主原型 / `DESIGN` / `PRODUCT-RULES`）当 context（在仓库里跑 + 读脊柱 = 懂产品、不脱实凭空编）→ 落 `deliverables/` + `INDEX.md` 登记 → **skill = 固化的临场**（默认临场生成，反复用 / 要统一格式才固化成 `make-*`）。新增 `deliverables-INDEX.md.tmpl`。已有产物入口：`prd-writing` standalone（已读脊柱）/ gstack `make-pdf`（发布级 PDF）。
- `fix(scripts)`: **attachments helper rewire 到六步锚点**（解除一条消费仓 sync 阻塞）。`_lib/attachments.py` 的 `_stage_doc_exists`（stage_prefix → 期望文档映射，决定 `pending_inject`）从旧 7-stage 锚点加上**六步锚点**：主 `req-plan`（②范围确认主产物）+ `task-plan` / `prd` / `close`；旧 `brief` / `analysis` / `impl` 保留兼容在飞旧 req。caller 侧 `attachments-upload.md` 早已在 skill 级联里改成六步主路径（new-req / next 范围确认 / task-plan / prd-writing），本批只补上 helper 这一处遗漏。加 `req-plan` 锚点回归测试，基线 **536 全绿**。（注：消费仓整体仍暂勿同步——剩在飞旧 req 状态值越界一条。）
- `fix(skills)`: **行为审 system mode 真 auth 落地（task-verify 步骤 4.5）**。从"占位/defer"做成真逻辑：登录后页面行为审走两条路——**路 1（默认）登录能用 UI 走通**（账号密码表单 → 后端发 session cookie），把「登录」作为验收流程第一步写进 `_plan.md`，`/browse` 跑一遍同 session 自然带登录态，**不需要外部导入**（prototype mock auth + system mode 表单可登录都走这条）；**路 2** 仅 system mode 真 auth 且**登录非表单可走**（外部 SSO / OAuth / MFA / captcha）才用 gstack `/setup-browser-cookies` 导真 cookie（带 macOS Keychain 弹窗、破坏无人值守，仅必要时走）。AI 读 `工程结构约束-{prototype,system,custom}.md` / `PRODUCT-STATE` 判本页 mock / system。
- `feat(scripts+skills)`: **并行多 task build + worktree 并发加固（v2 状态物化）**。① **并行编排**：`/pmai-next` build 阶段按 task-plan 拍的执行模式（串行 / 并行 / 混合）派发——并行时把依赖已满足、互不冲突的 task **各派一个独立执行器并发建**（各自 locked worktree + 各自执行器），全建完 + 各自三道审后**逐个呈交 PM**（建并发、呈交仍串行）。② **一 task 一执行器铁律**（2026-04-22 串台根因的结构化根除）：并发时绝不让一个执行器一口气干多 task——写进 next 驱动 + executor-dispatch subagent prompt（「只建这一个 task、不碰其它 worktree」）。③ **worktree lock 加固**：`create-task-worktree.sh` 建时 `git worktree lock`；`close-task.sh` / `task-transition.py`（discard）/ `cleanup-pending-worktrees.sh` 删前先 `unlock`——防一个 task 的清理 prune 掉另一个在跑的 worktree。④ 回归测试 `test-worktree-lock.sh`（建即 locked + lock 挡裸 remove + unlock 可删）。基线 **535 全绿**。**设计取舍**：原 v2 计划的 chmod 物理写约束**不适合并行**（同 uid 多执行器无法互相只读），改用**结构化防线**（一 task 一执行器 + dispatch 越界保护）防跨 task 串台，lock 专管移除竞态；真 Codex 对 lock 的 fs-level 约束力 POC 经 PM 决定不阻塞落地。**POC 已跑（2026-05-30）**：codex `workspace-write` 实测**放行整个 `$HOME`**（cwd / `writable_roots` 都收窄不动它），`git worktree lock` 不拦 fs 写——**外部执行器无法靠 config 物理关进 worktree**。PM 拍 **A 接受残留**：结构化防线（一 task 一执行器 + 越界保护扫自己 worktree 超界文件 rollback）足以挡 2026-04-22 事故形态（往自己 worktree 堆别 task 代码）；执行器故意写绝对路径到兄弟 worktree 物理拦不住但非历史形态 / 低概率；真物理隔离（容器 / 独立 uid）对单人工具不成比例、不做。
- `fix(skills)`: **行为审执行机制定稿（task-verify）**。① 删掉步骤 5 那张硬编码「PM 动作→浏览器操作」映射表（任何新句式都得回去改表 = 机械化债），改成把范围清单派生的**验收流程原文当 prompt 注入** gstack `/browse` + 一段**固定纪律 prompt**（严格逐步走 / 不自由探索 / 每步 assert / 失败截图继续 / 断言优先用可见文案）——**确定性来自注入的流程文本 + 纪律 prompt，不来自换工具**。② 明确**用 `/browse` 不用 `/qa`**：`/browse` 物理无 Edit/Write 权限 → 天然只报不改；`/qa` 会自动改代码 + 强制 clean working tree + 出健康分，撞「只报不改 + 确定性」。③ 行为审**驱动亲自跑**（不另起独立 agent）——客观二值 assert 无自审盲区，独立性由浏览器客观裁判提供。④ 步骤 1 对齐单窗口（删 `claude --add-dir` + auto-cd，改 `git rev-parse --git-common-dir` 解析 + 显式目录）。⑤ 加登录态 cookie 条件分支（默认跳过，仅真 auth 触发；完整接线留演进）。基线 **533 全绿**。
- `feat(scripts+skills)`: **build 执行器：可插拔独立 AI（PM 指定 claude / codex / cursor / gemini）**。① 新增 `gemini` 执行器——`exec-adapters/gemini.sh`（照 cursor-agent 无 sandbox 模式）+ `resolve-executor.py` VALID_EXECUTORS + settings/task 模板取值。codex/cursor/gemini 走各自独立 CLI（dispatch 的 `${EXECUTOR}.sh` 分支自动接）。② `claude-code` 执行器从「驱动当前实例 inline 建」改成「**驱动 spawn 独立 Claude subagent** 去隔离副本里建」——和 codex/cursor/gemini 一样独立（保隔离 + 角色分离 + failable 沙盒、PM 窗口对话不被建码刷屏）。③ task-execute 措辞翻正：build 由 **PM 指定的独立执行器**干、**驱动只编排**（定位/派发/越界检查/commit/三道审/呈交），不 inline 建。基线 **533 全绿**。
- `fix(skills)`: **task-execute 对齐单窗口模型**——build 这步唯一没跟上单窗口收敛的文件（task-confirm / close-task 早已收敛）。删掉「`claude --add-dir` 起独立会话 + auto-cd 进隔离副本 + 沙盒 reset 自检」整套多窗口机制，改成 AI 在 PM 当前窗口用 `git -C "$TASK_WORKTREE"` / 子 shell 显式目录操作隔离副本（不依赖会话 cwd 持久化）；`MAIN_REPO_ROOT` 经 `git rev-parse --git-common-dir` 从任意位置稳健解析。验收通过后 AI **自动接 close-task 收尾链**（不再提示 PM 切 req 窗口手跑），删残留的「close-task 两阶段 / Phase 2」陈旧引用。PM 全程零窗口切换。基线 **533 全绿**（含 `e2e/v4_T22_single_window_lifecycle` 端到端）。
- `feat(scripts)!` **六步坍缩引擎（BREAKING）**：`stages.py` 7-stage → per-req 四阶段（**1 范围确认 → 2 build → 3 复审 → 4 沉淀**；① 上下文脊柱 = init 项目级、不算 req stage）；`req-transition.py` 重写——`MAX_STAGE=4`、删 stage-4 DESIGN 跳过 / stage-3 prd-solution 前置 / stage-6·7 回退专属逻辑，stage 1 前置产物 = `req-plan.md`，沉淀（4）不可回退、复审（3）回退要求 task 已确认。迁移 3 个 stage 专属测试套（req-transition / stage-source-helper / pre-dispatch-doc-gate），删 8 个 7-stage 独有用例（DESIGN-skip / prd-solution / office-hours-fallback）。基线 548 → **540 全绿**。**⚠️ 消费仓暂勿同步本批**：24 skill 的 prose 仍引用旧 7-stage、尚未级联；在飞旧 req（stage 5-7）状态值在新机器下越界。待 skill 级联 + 旧 req 迁移方案完成再放同步。
- `feat(skills)!` **六步级联：22 skill + _shared 全改造（BREAKING）**：
  - **砍**：req-stage-gate → 薄壳（推进驱动搬到新建的 /pmai-next）。
  - **新建**：`skills/next`（/pmai-next）—— 六步推进主驱动（读当前阶段做下一步、先说再动；范围确认门接 check-open-questions 强制答题）。
  - **降后台**：req-analysis / implementation-design / task-spec / task-confirm / close-task / task-verify（机器保留、移出 PM 主视图）。
  - **改造**：init-project（建脊柱四件套 + prototype/ 脚手架 + 选 mode）/ new-req（三条上坡路 → req-plan）/ task-plan（task=demo 单元 + 范围清单/决策页）/ task-execute（栈内 build + 三道审 coverage-reviewer·design-review·browse + 体验迭代）/ task-status（产品轴）/ close-req（沉淀两档）/ prd-writing（后移按需、真系统口径多源合成）。
  - **合并**：task-submit → task-execute 呈交闸门；doc-update → close-req 沉淀。
  - **_shared**：input-flow（哪个 skill 读什么改六步）/ banner-rules（四阶段示例）/ PM-VIEW-RULES / attachments-upload（caller 改新主路径）。
  - 迁/删钉旧机制的测试（speed-mode / office-hours-B 分支 / stage-gate wiring / gap-check / 旧 trigger-0）。基线 540 → **533 全绿**。
  - **⚠️ 消费仓仍暂勿同步**：attachments stage_prefix rewire、build 三道审脚本级接线、藏显示产品轴、自动托管加固 spike、阶段2 真实 req spike 尚未完成；且在飞旧 req 状态值越界。
- `chore(scripts)`: 砍 `req-transition.py` 死代码 `check_design_md_has_content` / `find_repo_root`（stage-4 跳过随六步坍缩移除后无人调用）。
- `feat(scripts)`: status-view narrative/status **转产品轴 lead** —— 先念 PRODUCT-STATE 产品现状一句话 + 在做什么需求（`{阶段名} 阶段`），stage 编号退为次要语境、不再 lead；驱动文案改 /pmai-next。
- `fix(scripts)`: `status-view.py` / `_lib/state.py` 的 banner `/7` 硬编码 → `/{MAX_STAGE}`（skill-header banner 仍留轻量阶段锚点）。
- `feat(templates)`: 新增三个脊柱模板 —— `PRODUCT-STATE.md.tmpl`（产品现状层 hub：当前功能 / 主原型现状 / 实现深度状态 / 索引；只在沉淀时更新）、`req-plan.md.tmpl`（per-req 实现文档：范围清单 + 关键决策两节）、`DESIGN.md.tmpl`（正向视觉约束 + 产品化 demo 目标 + UI 习惯）。属重构「薄脊柱」首批；**尚未接线**（init-project / new-req 改造在后续 commit）。设计真相源见 `docs/设计/PMAI重构方向-office-hours收敛.md` + `docs/设计/PMAI重构-实施清单.md`。
- `feat(agents)`: 新增 `coverage-reviewer` agent（build 后覆盖审计：白纸视角拿 req-plan 范围清单 vs prototype 代码硬 diff，报建了 / 丢了 / 降级占位；对标 `analysis-reviewer`、不参与 build 防自审盲区；只做静态读码核对存在，视觉 / 行为 / 架构归 design-review / browse / 其他）。`.claude/agents/` 加同款 symlink。尚未接线（build 三道审在六步坍缩批接入）。
- `feat(templates)`: 新增 `prototype-README.md.tmpl`（主原型说明：单一主原型不留 fork、按 mode 实现深度、视觉照 DESIGN、原地重写转真）。prototype/ 代码脚手架本身由 init-project 用 `create-next-app` 起（后续 commit 接线）。

---

## 已发布版本

### 2026-05-27 — 12 个用户决策 skill 全部 picker 化（v5 PM 视图统一收敛 第二批）

**触发**：上一条 req-stage-gate 全门 picker 化只动了 stage 流程 orchestrator。PM 想"所有让用户决策的 skill 都 OK"，跑 audit 发现 12 个 skill 里只有 2 个完全 picker 化、6 个还在 prose、4 个部分 picker 化。

**改动**（每个 skill 顶部 M4 引用统一升级 + 主 prose 决策门改 picker）：

| Skill | 主要改动 |
|---|---|
| `close-task` | 0.3 B 类对齐 / 1.2 计划外简化 / 1.5.2 拿不准分类 / 1.6.3 跨功能规则 / P2.4 关 req 门 全 picker 化 |
| `close-req` | 1.5 rewrite vs patch / 2.5 候选孤儿三选一 / 2c 项目级同步 全 picker 化 |
| `task-execute` | 入口步骤 2.4 drift 整体策略 + 逐文件 picker / 步骤 12 PM 验收 picker（通过 / 打回） |
| `task-submit` | 步骤 4 PM 验收 picker（通过 / 打回） |
| `new-req` | 步骤 3 brief 引导方式 picker（AI 引导 / 我自己写）+ 二次确认 picker |
| `quick-fix` | 步骤 3.5 决策性 vs 轻量分类 picker；顶部加 M4 引用 |
| `prd-writing` | standalone 模式步骤 0 三选一对话 → 三连 picker（写哪部分 / 产物路径 / 输入清单）；顶部加 M4 引用 |
| `project-solution` | 步骤 6 最简 / 详细 / 混合三选模式 picker；顶部加 M4 引用 |
| `pmai-upgrade` | Step 2 升级模式四选 picker + D 暂缓子流程二级 picker（1 天 / 1 周 / 永远）；顶部加 M4 引用 |
| 顶部 M4 引用统一升级 | init-project / task-confirm / task-submit / task-execute / new-req / close-task / close-req / skill-improve 八个 skill 的「§1 3 硬规则」→「§1 四条硬规则」+ 加 Runtime 兜底重申 |

**未改的（设计上保留）**：

- `task-confirm` 步骤 6 执行方式列表（informational + PM 被动选；不是阻塞门）
- `skill-improve` 步骤 4 用 multiSelect（已 picker 化，>3 项分组形式不强制改）

**业务仓影响**：

- 所有 PM 决策门变成 picker 卡片 + 编号 fallback。PM 高频触发的 close-task / close-req / task-execute / task-submit 全统一形态。
- 续跑模式（PM 答"OK"自动推进）失效，PM 必须显式选 picker 选项（点击 / 输数字 / 输 label 关键词）。
- 模糊词（"OK / 通过 / 差不多了"）AI 反问澄清而非默认推进（按 askuser-rules.md §1.1）。

---

### 2026-05-27 — Stage 3/5 重命名 + req-stage-gate 全门 AskUserQuestion picker 化 + stage 转换标题加名字

**触发**：消费仓 ExampleConsumerApp req-009 反馈三处 PM 视角不对劲 ——
(a) Stage 1→2 三选一里「开放探讨 —— 像聊天一样发散聊，不另做复核」描述让 AI 把 PM 的 ChatGPT 对话 JSON 当 B 分支 office-hours 产物 snapshot，跳了 reviewer + 未决问题闸门，brief §6 列了 5 个未决题完全没收敛；
(b)「功能规格」/「模块规格 + task 拆分」是工程文档化称呼，PM 心智里 stage 3 就是「需求方案」（WHAT），stage 5 就是「实现设计」（HOW）—— 词典对不上时 PM 一句「进入方案设计」AI 会困惑指 stage 3 还是 stage 5；
(c) prose 列选项让 PM 自然语言回答的形态（v3/v4 续跑模式）让 AI 错解模糊词（"OK / 差不多"），所有 stage-gate 门改 AskUserQuestion picker（runtime 不支持时退化数字编号）。

**改动**（PM 视角）：

**1. stage 重命名**

- `scripts/_lib/stages.py` `STAGE_NAMES[3]`「功能规格」→「需求方案」；全仓 stage 3 名 / `prd.md` 描述里的「功能规格」→「需求方案」（22 处，跨 `req-stage-gate` / `prd-writing` / `implementation-design` / `task-spec` / `quick-fix` / `input-flow.md` / `CLAUDE.md.tmpl` / `task.md.tmpl` 等 SKILL & 模板）。docs/modules 语境里「模块功能规格 / 主功能规格文件」**保留不动**（指模块 spec 文件，跟 stage 3 名无关）。
- `STAGE_NAMES[5]`「模块规格 + task 拆分」→「实现设计 + task 拆分」（仅 `stages.py` 一处；其他「模块规格」指 docs/modules 文档保留）。

**2. req-stage-gate 全门 AskUserQuestion picker 化**

- Stage 1→2 主选择门：picker 三选一（AI 帮我分析 / 用 office-hours 风格分析 / brief 还要改）；B 选项从"前提式"（已跑过 office-hours 才能选）改成"动作式"（选这个就用 office-hours 分析，内部探测已有产物或引导现跑）。
- Stage 2→3 推进确认门：picker 二选一（进设计系统 / 继续修订 prd）。
- Stage 2 未决问题闸门：picker 二选一（逐题问我 / 先改 analysis 某段）。
- Stage 2→3 B 分支 office-hours 三态门（SLUG 失败 / 找到 N 份 / 没找到）：每态 picker 多选一（现在跑 / 选 1 份 / 自己指定路径 / 换 AI 帮我分析）。
- Stage 4 步骤 4B 确认门：picker 二选一（进 stage 5 / 继续调整组件规格）。
- Stage 4→5 步骤 5a-gate 决策门：每条结构决策（HOW-NN / SIMP-NN / 自由度声明）单独 AskUserQuestion（按 askuser-rules.md §1.4 多决策拆开顺序问）。
- Stage 5→6 步骤 4 task-plan 决策门：每条结构 task 单独 picker。
- Stage 5→6 步骤 5 入口总览门：picker 三选一（进 stage 6 / 回看某项 / 回卷 stage 4-5）。
- Stage 6→7 关 req 确认门：picker 二选一（关闭 req / 还要开新 task）。

**3. stage 转换标题加 stage 名字**

- 旧顶部标识 `Stage N（名字）— <产物> <状态>`（v3 书面体规则）→ 新统一 `Stage N <名字> → M <名字>`（转换式，含起止两 stage 名）。
- `### Stage X → Y` 段标题补全缺漏的 stage 名：Stage 3→4 补"设计系统建立"、Stage 4→5 补"设计系统建立"、Stage 4 标题补"设计系统建立"、Stage 5→6 补"实现设计 + task 拆分"。

**4. 架构规则更新**

- `skills/_shared/pm-view/banner-rules.md` §3.0 表格：**废止 v3/v4 续跑模式专门豁免**（旧规则把 stage-gate 选择门 / 推进确认门归到「chat prose 不走 §3」），改成「任何 PM 决策门必须用 AskUserQuestion，runtime 不支持时退化编号列表」。
- §1.2 banner 例子 stage 名字从 "PRD-Writing / QUESTIONING / Task-Spec → Execute" 等过时英文改成 `STAGE_NAMES` 中文真值。
- `skills/_shared/pm-view/askuser-rules.md` §1.3 加编号规则：AskUserQuestion picker label **不带数字前缀**（picker UI 本身是按钮）；只退化模式带编号（PM 输数字回复是最快路径）；退化模式必加"请回复编号（或自由文本说明）"收尾。

**业务仓影响**：

- `.req-meta.json` 里 `stage` 字段仍是数字，**不受影响**；STAGE_OUTPUT_FILES 产物文件名（brief.md / analysis.md / prd.md / task-plan.md）**不变**。
- PM 视角：所有 stage-gate 确认门从"prose 列选项 + 自然语言回话"变成"picker 卡片 + 点选/数字/关键词回话"。续跑模式（PM 答"OK"自动推进）失效——PM 必须显式选 picker 选项（点 / 输数字 / 输 label 关键词）。
- 模糊词（"OK / 通过 / 差不多了"）AI 反问澄清而非默认推进（按 askuser-rules.md §1.1）。
- 已经在飞的 req 不受影响（旧 prd.md / task md 里的「功能规格」字面残留属于历史档案，不强制回填）。

---

### 2026-05-26 — task-execute 审计闭环加固（修复 A + B + C + C'）：堵 dispatch 没跑就推状态的悬空窗口

**触发**：消费仓 ExampleConsumerApp req-008 task-001 复现 req-006 同款事故 —— AI 进 /pmai-task-execute 后入口前置 transition 了「待执行→执行中」，但中断 skill 没跑 dispatch 节点，直接用 Edit/Write 完成 work + 3 commit；事件流卡在仅 1 条 `status_changed`，accept 闸门正确拦下 `--to 已完成`，但 AI 给 PM 误诊"infra bug, skill 没自动 append"+ 提议 `task-events.py append --type execution_started` 补登（伪造审计证据）。req-006 后的 accept 闸门兜底有效，但缺**物理约束**让伪造路径根本执行不了 + 缺 AI 故障恢复的合规出口。

**改动**（PM 视角）：

- **修复 A**：`scripts/task-events.py` CLI 加黑名单 —— `execution_started` / `execution_manual_completed` 不允许通过 `task-events.py append --type ...` 写入；错误消息直接列举合规出路（`/pmai-task-execute` / `--register-manual-completion` / `--repair-evidence`）。`scripts/_lib/events.py` 加 `CLI_RESTRICTED_EVENT_TYPES` 常量 + `append_execution_event_internal()` 内部 API。
- **修复 B**：`scripts/task-transition.py` 「待执行→执行中」transition 加 `--bound-to-execution-event {started, manual-waiting}` 必填参数；与 dispatch event 原子绑定写入（`_lib/events.py` 加 `write_status_change_and_exec_event_atomic()` 一次 `fh.write` 写两条）。裸 transition 拒绝；状态已=执行中 + 带 bound flag 视为 dispatch retry（emit dispatch event 不动状态）。
- **修复 C**：`scripts/task-transition.py` 加 `--register-manual-completion --reason "<...>"` 命令 —— AI 故障恢复合规出口（task 状态=执行中、事件流缺 exec event、worktree 有 task commit 时用）。强制 `--reason` + 验 worktree 真有 commit + 写 `execution_manual_completed` with `{repaired:true, by:manual-completion-register}` payload + 不动状态。
- **修复 C'**：`scripts/task-transition.py` 加 `--emit-from-pending` 命令 —— dispatch §3a manual resume 合规通路（需 PENDING_FILE 存在）；写 `execution_manual_completed` + 删 PENDING_FILE + 不动状态。
- accept 闸门错误消息（`task-transition.py check_preconditions`）加合规出路列表 + 明确"禁止 task-events.py append 绕过"。
- `skills/task-execute/SKILL.md` 入口前置 step 3 不再自己 transition；transition 移到 §3b dispatch 节点（atomic 绑 dispatch event）。
- `skills/task-execute/references/executor-dispatch.md`：§3a manual resume 改调 `task-transition.py --emit-from-pending`；§3b 正常 dispatch 改调 `task-transition.py --to 执行中 --bound-to-execution-event {started|manual-waiting} --executor X ...`（按 executor 类型分流 bind type）。
- `scripts/exec-adapters/manual.sh` 去掉 emit `execution_manual_waiting`（由 §3b atomic transition 在 manual.sh 之前写入）。

**事故路径对照**：

| 缺口 | 物化约束（修复后） |
|---|---|
| AI 用 `task-events.py append --type execution_started` 伪造审计证据 | A：CLI 直接拒绝 |
| AI 进 /pmai-task-execute 后 transition 了但不跑 dispatch（事件流悬空）| B：transition 必须绑 dispatch event |
| AI 用 Edit/Write 自己做完 work 后无合规补登入口 | C：`--register-manual-completion` |
| dispatch §3a manual resume 通路曾走 CLI（A 后会拒）| C'：`--emit-from-pending` 内部 API 写 |

**影响**：

- 业务仓 task-execute 同步框架后所有 task 自动适用；既有"已完成" task 不受影响。
- 业务仓如有"卡在执行中、事件流缺 exec event、worktree 有 commit"的故障 task（事故场景），同步后 AI 可调 `--register-manual-completion --reason "..."` 走合规补登 → 再走正常 `task-submit` / `--to 已完成`。
- 测试基线 527/0 全绿（+13 新 case for A/B/C/C'）。

### 2026-05-26 — DESIGN.md 全流程重构（gstack 写视觉基线 + 框架管 inventory + 自由度声明移 implementation-design）

**触发**：PM 反思 DESIGN.md 5 个写入点（init 留空骨架 / new-req 兜底 / stage 4 4A 占位 / stage 4 4B 视觉规范更新 / close-task 视觉反馈反推）混乱，定位"乱"的根因 = ① DESIGN.md 视觉基线未在 init 阶段共写、推迟到 req 级 → 把项目级决策塞进 req 流程 ② executor 在视觉规范没说的地方乱搞 ③ 创意自由度三档归属错位（项目级文档写 req 级决策）。

**改动**（PM 视角）：

- `/pmai-init-project` 加阶段 C.5（视觉基线必填）：调 gstack `/design-consultation` 全跑 → 写 DESIGN.md 头 8 段 → AI 追加「共享组件 inventory」空段 → PM 定稿确认 → commit。4 阶段 → 5 阶段（A/B/C/C.5/D）
- `templates/DESIGN.md.tmpl` 删除：DESIGN.md 由 gstack 写 + AI 追加 1 段，不需要静态模板。`init-project.sh` 砍 DESIGN.md.tmpl 拷贝行
- `/pmai-req-stage-gate` Stage 4 砍 4B 视觉规范更新分支，4A 改"新组件完整规格定稿"硬约束（PM + AI 共写视觉/状态/交互/边界，task 启动前 inventory 必须完整；不再 close-task 回填占位）
- `/pmai-build-close-task` §1.5 改 4 类分流（① task 实现偏差不动 DESIGN / ② 视觉基线 patch gstack 段 / ③ inventory patch / ④ 文案 voice & tone 拒绝写 DESIGN，建议改 PROJECT 或 prd）
- 创意自由度三档从 DESIGN.md 移到 `implementation-design.md` 段 3.3「自由度声明」（req 级，task-spec 按"适用范围"挑行写进 task 文件，stage 5 5a-gate 视作结构决策必 PM 拍板）
- DESIGN.md 砍 a11y 独立段（PM 决定）+ Checker Sign-Off 段（搬进 init C.5 SKILL 自检流程）
- `/pmai-new-req` 步骤 3.6 改：旧版"6 段骨架 mini-upgrade"砍，新版"检测 inventory 段是否存在，缺则追加空段"

**集成 gstack 的决策**：不抄 gstack 任何内容到我们 SKILL.md（gstack 升级时跟不上）；直接调它的 skill，跟随升级。下游 SKILL 不解析 gstack 写的 8 段字段，只读「共享组件 inventory」段（我们追加 / stage 4 4A 累积 / close-task §1.5 patch）—— gstack 自由演化我们自动兼容。

**影响**：
- task executor 启动时 DESIGN.md 是完整硬约束（视觉基线 + 本 req 新组件完整规格 + 段 3.3 自由度声明）—— "没规范可循"的灰色地带消失
- PM 触点从 5 处简化为 4 处：init C.5（gstack 主导）/ stage 4 4A（共写规格）/ close-task §1.5（分流沉淀）/ PM 任意时机调 `/design-consultation`
- 测试基线 515/0 全绿（删 6 个旧 case + 改 3 个 + 新增 0 个）

### 2026-05-26 — term-detector 调用点收敛到 prd-writing 一处

**触发**：实际跑 brief 阶段 detector 跑出 16 个候选词，全为 PM 修辞强调（`**真正的痛点**` 类），PM 全跳过 = 浪费确认门；PM 同时反馈"不知道术语表有什么用"。查清术语表实际作用：给 AI 读 `PROJECT.md` 时当背景词典（无 lint 强校验），是弱价值机制。

**改动**：
- `skills/new-req/SKILL.md` 砍步骤 4.3「业务词催补 hook」（brief 阶段 PM 自由描述，业务词还在变 + `**` 多为修辞，detector 信噪比差）
- `skills/req-analysis/SKILL.md` 砍步骤 3.5「业务词催补 hook」（analysis 阶段业务词还在变，登记早）
- `skills/req-stage-gate/SKILL.md` 4B「B 分支 term-detector hook」整段砍掉，并入「B 分支不跑」清单
- `skills/_shared/term-detector/SKILL.md` 调用矩阵收敛到只剩 `prd-writing` 步骤 3.6 一处；description / 何时调用 / 禁止位置全段重写，注明 2026-05-26 收敛理由
- `prd-writing` 步骤 3.6 detector 调用保留（PRD 定稿 = 业务词稳定时机，是建术语表唯一合理时间窗）
- `scripts/_lib/term-detector.py` 候选源去掉 `**X**`（markdown 加粗），只保留「X」/『X』/""（显式术语标记）—— 中文 `**` 几乎只用于修辞强调，误报率压倒任何真业务词收益；docstring 同步更新

**影响**：detector 召回次数从 ~3 次/req → 1 次/req；噪音源（`**`）干掉；术语表"何时建"边界变清晰（PRD 定稿一次性催补）；测试基线 482/0 无回归（无 detector 专门测试）。

### 2026-05-26 — D-iv v0.3 patch F1：req-stage-gate 续跑模式概念收敛

- `skills/req-stage-gate/SKILL.md` 续跑模式段顶部加 TL;DR 1 句话答案（"PM 只敲 1 次，AI 自动续跑 stage 1→6"）；详细规则（2 个退出条件 / 不是退出条件 / 核心边界 15 行）折叠进 `<details>`；保留"PM chat 输出格式"段不折叠（AI 执行指引，不能藏）
- 修审计 F1：新手 PM 在 35 行铺垫中找"敲一次还是每 stage 敲一次"的答案，TL;DR 直接 1 行给出
- 无新增测试（纯文档结构调整）；测试基线 460/0 持平

### 2026-05-25 — D-iv v0.3 patch：新手 PM 视角审计 3 BLOCKER 直修

**触发**：subagent 模拟新手 PM 走完整 init→new-req→stage-gate→task→close 流程，报 3 BLOCKER + 3 FRICTION。3 BLOCKER 已 verify 为真，本次直修。

**改动**：
- `skills/task-confirm/SKILL.md` 顶部指针删「执行前确认闸门 label」（与 body 行 23-25 delta-3 §2.3「不再设确认闸门」自相矛盾，原是 vp-8 后期加指针时未同步 body）
- 5 个用户面 SKILL Preamble 段（new-req / req-stage-gate / task-confirm / close-task / close-req）加 `python3 .claude/scripts/status-view.py --banner-only --skill X || true` —— banner 真在 body 里调用，不只是顶部 prose 指针
- 2 个 SKILL（init-project / task-execute）用字面值 `echo "━━━ PMAI ► ..."` —— init-project 是项目级（生成器仓内跑、无 active req），task-execute 入口前置阶段尚未 cd 到 task worktree
- `scripts/status-view.py:render_banner_only` 无 active req 文案由「先跑 /pmai-new-req」改通用「<项目级 / 无 active req>」（对 /pmai-init-project 不再误导）
- 7 SKILL 退出文案补 `▶ Next Up` 关键词（task-confirm 行 206 ▶️→▶ + new-req 步骤 5 handoff + req-stage-gate 退出 + task-execute 步骤 12 通过分支 + close-task Phase 1→2 + close-req Phase 1→2 + close-req Phase 2 终态）
- `close-task` Phase 1→2 / `close-req` Phase 1→2 切窗口给完整可复制命令（"窗口还开着直接切 / 窗口已关用 cd + claude" 两条路径）
- `skills/req-stage-gate/SKILL.md` stage 6→7 blocked 错误信息扩展「废弃 task 三步」可复制命令链（mv 到 tasks/discarded/ + 改 task-plan.md `## 变更记录` + 加 task 文件「废弃理由」段），堵 PM 手动跳 task 时 metadata 不一致风险
- `skills/_shared/pm-view/banner-rules.md` 新加 §3.0 适用范围 —— §3 3 硬规则**只管 AskUserQuestion picker 形式**闸门（GUI 选项卡片），续跑模式 + chat 自由对话走常规形态不受 §3 约束（4 行判定表覆盖典型场景）。修 D-iv vp-7/8 上线后留下的"§3 vs 续跑模式互斥" tension
- `skills/req-stage-gate/SKILL.md` Stage 1→2 分流 B `gstack-slug` 解析改 fail-loud —— 旧 `SLUG="unknown"` silent fallback 让 PM 误以为"没探测到 office-hours 产物"（实际是 slug 没解析对）；新代码拆三态 (I) slug 失败显式告 PM 原因 (II) slug OK 找到 (III) slug OK 没找到
- `tests/test-banner-label.sh` 新增 T6-T10（7 SKILL body 真调 banner / 退出处含 ▶ Next Up / task-confirm 不矛盾 / §3.0 适用范围 / slug fail-loud）防回归

**业务仓需注意**：
- 同步后每个 SKILL 入口都会打 banner（`━━━ PMAI ► SKILL ▸ <stage> ━━━`），PM 切窗口回来不再"失忆"
- `/pmai-build-close-task` Phase 1 完成后 chat 输出有完整 cd 命令；`/pmai-build-close-req` 同
- 跳 task 三步走（不再是含糊的"从 task-plan.md 删除该条"）
- **未新建** `/cancel-task` skill —— PM 实际跳 task 频率不高，三步手动可接受；若消费仓验证发现频繁要跳，再开新 vp 做 skill
- **§3 适用范围**：以前 vp-7/8 引导 SKILL 顶部写「闸门 label 按 §3」是过度承诺；现在明确只 AskUserQuestion picker 形式才走 §3，chat 自由对话不受约束。SKILL.md 顶部 prose 指针该词原文不动（仍引用 §3），但消费方应按 §3.0 适用范围判定
- **office-hours slug fail-loud**：消费仓若没装 gstack 或本项目未 gstack 注册，跑到 Stage 1→2 office-hours 分流时会显式报错（不再误说"没探测到产物"），PM 看到 stderr 原文知道是 slug 解析失败、直接走指定路径 / 切结构化批判分流

**测试基线**：`bash tests/run-all.sh` **460 / 0**（前 455/0 + 本次新增 5 case；无回归）

### 2026-05-09 — I-DC1 文档落盘 gate（task-005 文案偏差事故根因修复）

**事故**：ExampleConsumerApp task-005 三个状态变更弹窗 + 导入弹窗的实施文案与 PM 视图终态偏差。根因是 task-spec 跑了 4 轮 revise + 1 次 reconcile，全部停在 req 分支 working tree 没 commit；task-confirm 通过 `git worktree add -b ... <REQ_BRANCH>` fork 时取的是 req 分支 HEAD commit（first-gen v1），把 PM 改了 4 次的版本完全跳过，executor 按 v1 实施。

**修复**：把 I-AD5「dispatch 前 task worktree 必须 clean」推广到文档级 dispatch 边界，立 I-DC1 三道防线。

- 新增 `scripts/_lib/dirty-check.sh`：`list_doc_dirty` / `auto_commit_docs` 共享 helper（pathspec 严格隔离）
- `scripts/create-task-worktree.sh` 加 pre-fork dirty gate：fork 之前 auto-commit 本 task 的 PM 视图主文件 + 工程合同
- `scripts/req-transition.py` 加 pre-transition gate：forward 推进时 auto-commit active req 范围内（含 `docs/DESIGN.md`）的未 commit 文档；rollback 不触发
- `skills/task-spec/SKILL.md` 新增步骤 12.6：reconcile 出口处由 skill 自身 commit task md 两文件到 req 分支（首道防线，PM 不感知；commit 字样列入步骤 12 chat 禁词清单）
- `INVARIANTS.md` 立 I-DC1（60→61 条），主索引加 `I-DC` 行
- 新测试套 `tests/test-pre-dispatch-doc-gate.sh`（10 条用例覆盖三道防线）

**业务仓需注意**：

- 同步后 task-spec 步骤 12 PM 一句"OK"会自动 commit 两文件到 req 分支，commit message 模板 `task-NNN-<slug>: spec sealed (hash <12chars>)`；PM chat 输出禁词扩充 `commit` / `已落盘` / `git log` / commit hash / commit message
- task-confirm fork 前若 req 分支 working tree 仍 dirty（task-spec 12.6 应该已处理，未触发说明走过 fallback），脚本 stderr 输出 `⚠️ I-DC1 pre-fork gate` 警告 + 自动落盘后再 fork；SKILL 要求 AI 把警告原文转给 PM 一句话说明
- req-transition forward 推进若 active req / DESIGN.md 仍 dirty，脚本 auto-commit + stderr 警告，commit message 模板 `req: stage <N>→<N+1> seal docs`；rollback 行为不变
- 既有 close-task.sh 行 185 的 req worktree dirty check 仍保留（fail-late 兜底层）；I-DC1 把多数场景在更早阶段消化，close 时该 check 应永远 silent

### 2026-05-09 — DX 审计本轮收尾 + 3 项 gap 补丁

**主线**：`/gstack-devex-review` 活体审计第一轮（4.7/10）→ 9 项 P0 + 横向 2 入口 + P1-4/6 落地后第二轮活体审计（5.6/10，+0.9）。本轮收尾 + 修剩余 3 项 gap。

- `8096be3` refactor(docs): P1-4 / P1-6 内容补丁
- `cb601b8` refactor(docs): P1-4 task-plan 硬约束节合并 + P1-6 STATUS → RUNTIME 改名
- `0579198` refactor(scripts): 防御性指令反模式 — req 编号扫描 / 未决问题闸门 抽脚本
- `34b1d4d` feat(skills): /pmai-skill-improve 雏形 + 消化 prd-writing 反馈 3 项 gap
- `ea2dc82` refactor(skills): PM-VIEW-RULES + 三个超大 SKILL.md 按消费方拆 references

**业务仓需注意**：

- `skills/_shared/PM-VIEW-RULES.md` 943 → 278 行 + 6 子文件 (`pm-view/{writing-rules,doc-strictness,section-order,checklist,input-flow,cross-skill}.md`)；12 个 skill 引用路径已改为指向具体子文件。**业务仓 sync 后**，模板里 `PM-VIEW-RULES §X` 引用号仍可用（主文件做索引），无须改业务仓产物。
- 三超大 SKILL.md 拆 references/：`task-execute` 911→539、`prd-writing` 756→315、`task-spec` 568→525。SKILL 主文件留 frontmatter + workflow 大纲 + 关键规则；详细 dispatch / acceptance handoff / writing rules / few-shots / impl-prose-merge 等进 references/。
- 新增 skill `/pmai-skill-improve`：消化 PM 反馈到对应 skill 的流程（read 反馈 → 对账现状 → PM 决策 → 改 SKILL → 归档到 `skill-feedback/<skill-name>-<date>.md`）。业务仓不需要直接装这个 skill；当 PM 想改进框架自身 skill 时调用。
- 新增 `scripts/_lib/req-num-resolver.sh`：封装 req 编号扫描（closed 目录 / active 目录 / git refs 三来源取 max）；`new-req` SKILL §步骤 1 改为单行 helper 调用。
- 新增 `scripts/check-open-questions.py`：未决问题闸门 lint（扫 `## 未决问题` section 下 `**PM 回答：**` 占位是否填）；`req-stage-gate` Stage 1→2 步骤 4 改为脚本调用 + exit code 路由。
- `task-plan` / `req-solution` 「硬禁止项 vs Rules」合并成单一 `## Rules`（含「禁止项」+「正向约束」两个 sub-bullet 组），与其它 skill 对齐。
- 错误信息加第三层「修复指引」：`task-transition.py` task 文件缺失时给路径 + 修复路径；`check-open-questions.py` 同。

### 2026-05-08 — 错误监控 + 状态机收敛 + DX 审计开始

- `8affee9` fix(audit): CT7 旧规范三步式兼容 + CT8 chore commit 豁免
- `3a4a98a` refactor(scripts): worktree 物理路径解析抽 `_lib/worktree.sh` helper
- `38313a9` feat(skills): task-plan 反模式扩容 + close-req 覆盖度判断 + INVARIANTS 主索引（60 条不变量速查）
- `95dca9e` feat(scripts): worktree 残留检测脚本 + 集成 req-stage-gate
- `2560cb8` refactor(docs): 归档 21 份历史设计档案到 docs/归档/完成/

**业务仓需注意**：

- `INVARIANTS.md` 加 60 条不变量主索引（按 I-G / I-CT / I-CR / I-CA / I-CB / I-AD / I-RV / I-TT / I-RT 前缀分组）。业务仓 sync 后续把 SKILL 里 `I-XX1` 引用都能在主索引里 30 秒定位。
- `task-plan` SKILL §2.2 反模式扩容到 5 条（A 纯前置 / B 横切质量 / C 共生对 / D 同文件串行 / E 模块归属）+ §2.4 拆分后自检 5 项 + 启发式 task 总数 > 7 / 单模块 > 3 触发审查。
- `close-req.sh` 加 doc-update 覆盖度自动判断（步骤 2a/2b）：扫所有 closed task 的 `## 文档偏差` section，发现 `<!-- SKIP_DOC_UPDATE` marker 且 `cleanup_status="pending"` → 阻止 close-req 推进。
- 新增 `scripts/check-worktree-residue.py`：检测编号冲突 / 孤儿 worktree；req-stage-gate Preamble 集成（不阻塞，警告供 PM 处理）。
- 新增 `scripts/_lib/worktree.sh`：branch ↔ worktree 物理路径解析 helper。

### 2026-05-08 之前 — v3.5 实施全部收口

阶段 1 + 2 + 3 + 4 + 4.5（含 d 修订 + e patch + f sync 改造）完成；阶段 5/6/7/8/9 全部废弃 / 跳过。详细进度见 [`RUNTIME.md`](./RUNTIME.md) 「v3.5 实施进度」章节。

最近一次 v3.5 改造（2026-05-08）：状态机收敛 — 合并「待验收」入「执行中」 + 推荐 review 移到验收信息块末尾。

- task 状态从 5 态 → 4 态（待确认 / 执行中 / 已完成 / 已废弃；删「待验收」）<br/>  *（注：「待确认」于 2026-05-09 改名为「待执行」，避免与 task-spec 步骤 12 的"确认 task 内容"语义重叠）*
- 合法 transition 从 6 → 3
- PM 打回**不切状态**：写反馈到 PM 视图历史档案 + AI 续修 + 追加 fix commit
- 推荐 review 不再是 commit 前必经步骤；改作呈交块末尾「⚙️ 可选深度审查」辅助提示
- 影响范围：INVARIANTS.md（I-CB10 / I-CT7 / I-RV1-2 / I-TT1-4 / I-CA2）+ task-transition.py / audit-task-events.py / status-view.py / close-req.sh / req-transition.py / skill-preamble.sh + skills/{task-execute,task-submit,task-status,task-spec,req-stage-gate} + 8 个 test 文件 + fixture.sh

---

### 2026-05-27 — fix(new-req): cwd 护栏 + 4E 兜底 + Next Up 文案精简（防 AI 直接 cd "$WORKTREE_DIR" 污染主对话 cwd）

**触发**：PM 在消费仓跑 /pmai-new-req 时观察到 Claude Code status 栏路径从主仓切到 worktree —— 违反 SKILL.md 规则 441（主对话 cwd 不切 worktree 是 PM 视图契约，切分支事件必须由 PM 显式开新窗口触发）。

**根因**：AI 在步骤 4 debug pre-commit hook 时图省事用 `cd "$WORKTREE_DIR" && <cmd>`，没遵守现有 prose 规则的 `git -C` 写法。Claude Code Bash 工具 cwd 在多次调用间持久（工具说明明写），一次 cd 永久带走主对话 cwd，导致 PM 看 status 栏发现自己被拖进了 worktree 分支。

**修复**（`skills/new-req/SKILL.md`）：

- **步骤 4 入口加 AI 执行硬规则**（上游护栏）：表格列出 3 种安全形式（`git -C` / subshell `(cd && cmd)` / 工具 `--cwd`），明写"禁止直接 `cd "$WORKTREE_DIR"`"含顺手写法，并解释 Bash 工具 cwd 持久这件事
- **加 4E cwd 兜底**：handoff 前显式 `cd "$REPO_ROOT" && pwd`，4A-4D 听话时是 no-op；任一步意外切 cwd 都被本步骤拉回主仓
- **Next Up 文案精简**：3 步分行 + 段落注释 → 一行 `cd <path> && claude` + 一句 `/pmai-req-stage-gate`，减少 PM 误读（之前 PM 反馈"已经在 worktree 中还让我 cd" = IDE 视觉混淆 + 文案啰嗦叠加）

**影响**：业务仓续跑 /pmai-new-req 时 LLM 受护栏约束直接 cd 概率下降；即使临场失误，4E 兜底；handoff 文案 PM 视图更清爽。**与 PM-VIEW-RULES 一致**（不切 cwd 是 PM 视图契约）。

**触发**：PM commit 含 `attachments/` 小文件时，hook 无任何 stderr 输出但直接 exit 1，导致 commit 莫名失败，PM 只能 `--no-verify` 救火（违反守约）。

**根因**：`templates/git-hooks/pre-commit.tmpl` 末尾 attachments 大文件检测段
`STAGED_LARGE=$(... | while read -r f; do [...] && echo ...; done)` 在命中
`/attachments/` 路径且文件 ≤10MB 时，while body 末句 `[ ] && echo` 返回 1 →
while exit 1 → pipeline exit 1 → 命令替换失败 → 顶部 `set -e` 让 hook silent
abort（POSIX 行为：set -e **不豁免**赋值语句里的命令替换失败传播）。

**修复**：

- `done)` 后追加 `|| true`，让 warn-only 段失败不传播
- `set -e` 后加守约注释：后续 warn-only 段必须 `|| true` 结尾
- 新增 2 个回归 test case：`I-PCH10`（小文件不触发 silent fail）+ `I-PCH11`（大文件仍 warn 不 block）
- `tests/test-pre-commit-hook.sh` 11/11 通过

**消费仓同步**：跑 `bash $HOME/.pmai/scripts/install-hooks.sh` 在已安装项目刷新 hook 即可（pmai upgrade 后自动包含）。

---

### 2026-05-27 — feat(prd-writing): §六「原型」节 AI 现画 ASCII 原型图（替代文字意图描述）

**触发**：PM 反馈 PRD 现状 §6.X 模块「原型」节只写 1-2 句文字意图描述（"主要分区 + 用户主路径"），评审与下游 UI task 都拿不到视觉锚点。PM 要求 stage 3 写 PRD 时由 AI 现画 ASCII 原型，模块下每个页面 / 弹窗 / 抽屉各一张。

**改动（PM 视角）**：

- §六 每个 §6.X 模块的「原型」节由 **AI 现画 ASCII 原型图**（fenced code block 包裹）替代纯文字意图描述
- **数量规则**：模块下涉及几个页面 / 弹窗 / 抽屉就画几张，一一对应不省略
- **详细度**：中等（30-60 行，含表头列名 / 列表行示例 / 表单字段名 / 主要按钮文案）；不画像素 / 颜色 hex / 组件库名（DESIGN.md 范畴）
- **每张图上方 1 句文字兜底**：「这是 X 页面 / 弹窗 / 抽屉」+ 用户主路径；close-req 反向对齐时 ASCII 替换为真实截图，兜底句保留

**影响范围**：

- 模板：`skills/prd-writing/templates/req-prd.md.tmpl`（§六 顶部清单改成 ASCII 注释）
- skill：`skills/prd-writing/SKILL.md`（步骤 2 / 步骤 3 / 「PRD 结构」§六 / 功能需求表格写法「原型素材」段 / 质检 prompt 第 22 条 共 5 处）
- few-shots：`skills/prd-writing/references/few-shots.md` 新增「§六 原型节 ASCII 示例」段（角色列表页 + 新建角色弹窗 + 角色详情抽屉 3 张完整示例 + 4 条反例）
- lint：`scripts/check-prd-hierarchy.py` 的 `check_style` 跳过 fenced code block —— ASCII 里的 `▾` / ` · ` 不被类 2 描述风格扫描误报

**消费仓影响**：stage 3 起新 PRD 时 AI 自动现画 ASCII 原型；已写完的旧 PRD 不强制回填（仍允许文字描述）。close-req 反向对齐机制不变，仍用真实截图替换。

---

### 2026-05-27 — refactor(project-direction): 砍 PROJECT.md「产品路线」节 + status-view --milestone flag

**触发**：PM 跑项目方向讨论时撞到「PROJECT.md 产品路线节」和「ROADMAP.md」颗粒度撞车 —— 单人项目里"叙事性里程碑"和"req 队列"颗粒度天然糊，PM 在路线节列出"P0 / P1 / P2 + 具体功能"，转头 roadmap 又重列一遍，体感「同一组功能填两次」。

**根因（3 处共同造成）**：

- `PROJECT.md.tmpl` 路线节下挂「已完成 / 计划中」两子节 = roadmap 轻量版
- `_shared/project-questioning.md` §3 话术「先做什么后做什么」诱导 PM 答具体功能
- greenfield 提问顺序「路线 → roadmap」让 PM 先吐功能、被问 roadmap 又重列一次

**改动（PM 视角）**：

- **PROJECT.md 从 6 节减为 5 节** —— 砍「产品路线」节及「已完成 / 计划中」子节
- **ROADMAP.md = 唯一规划视图**（历史 done + 当前 active + 计划 planned 一张表）；叙事性里程碑废弃
- **status-view.py 砍 `--milestone` flag** + ⭐ 标记机制（路线节不存在了，里程碑 ⭐ 失依据）
- **close-req 步骤 3.5「里程碑追加询问」整段砍**（不再问 PM 把本 req 加进路线节）
- 各 skill 提问顺序去掉「产品路线」（init-project greenfield / project-solution A/B/C/D 4 场景）

**影响范围**：

- 模板：`PROJECT.md.tmpl` / `ROADMAP.md.tmpl` / `CLAUDE.md.tmpl`
- skill：`project-solution` / `new-req` / `close-req` / `prd-writing` / `_shared/project-questioning.md`
- script：`check-project-sections.py`（5 节）/ `status-view.py`（砍 `--milestone`）/ `_lib/state.py`（砍 `_load_milestone_set` / `is_milestone` 字段）

**消费仓影响**：已有项目 `docs/PROJECT.md` 里的「## 产品路线」节同步框架后仍保留，但 `check-project-sections.py` 不再检查它、`close-req` 不再问追加 —— 即历史内容不动、新机制不再写入。`status-view --milestone` 调用方报错（flag 已删），PM 不再用。

---

### 2026-05-27 — docs(drift): new-req 重排连带漂移点修复（3 处）

`refactor(new-req): worktree 创建后置` commit 后扫到 3 处 _shared / 其他 SKILL 仍引旧步骤号 / 旧 trigger 2 契约的漂移点，逐条补正：

- `skills/req-stage-gate/SKILL.md:544`「旧项目兜底由 `/pmai-new-req` 步骤 3.6 检测追加」→ 步骤 2B（DESIGN.md inventory 兜底已搬到新 SKILL 的步骤 2B）
- `skills/_shared/pm-view/banner-rules.md:121` AskUserQuestion 示例「`/pmai-new-req` 步骤 4 缺口补问」→ 步骤 3（缺口补问从原步骤 4 变 步骤 3）
- `skills/_shared/pm-view/attachments-upload.md` §2.2 / §6：加 new-req 例外段 —— trigger 0 在 new-req chat 时**不**立即调 `copy_attachment`，仅入内存 list `PENDING_ATTACHMENTS`，实际 batch 调用推迟到步骤 4B（worktree 创建后）；trigger 2 在 new-req 砍（worktree 还没建无 cp 目标），PM 想绕 chat → handoff 后在 worktree 新对话里做（stage 2+ caller SKILL 的 trigger 2 兜底）

**测试**：attachments-helper 16/16 / banner-label 10/10 / no-duplicate-questioning 4/4 全过。

---

### 2026-05-27 — refactor(new-req): worktree 创建后置 — brief 整理在 main，PM 二确通过后才拉 worktree 并 handoff

**触发**：消费仓 PM 跑 `/pmai-new-req` 给完需求后，AI 拿编号 + 问 slug → 立即 `create-req-headless.sh` 拉 worktree + `cd` 进去 → IDE 显示分支从 `main` 切到 `req-NNN-...`。PM 反应"你怎么切分支了"——主仓 main 工作区其实没动（worktree 是隔离机制），但视角等同于 IDE 切分支，PM 体验破绽。PM 明确"按之前的流程，应该是先整理 brief、再创建 worktree、让我手动切"（旧仓的 `docs/` 工作模式：所有 doc / 规格在 main 上整理，worktree 只用作 implementation 隔离）。

**根因**：当前 SKILL 步骤 3 一上来就拉 worktree + `cd`，导致 stage 1 brief 整理全程在 worktree 内进行。PM 视角下 worktree 隔离 = IDE 切分支，这个事件应该由 **PM 明确说 OK 之后才发生**，不是 AI 在 stage 1 中段就替 PM 切。

**改动**（PM 视角）：

- **worktree 创建后置**：拉 worktree 推到「brief 二确通过之后」的步骤 4 原子操作。步骤 0-3 全程主对话 cwd 在主仓 main、不创建任何文件/目录，brief 草稿在 chat markdown block 展示
- **PROJECT.md / DESIGN.md baseline 兜底搬到 main 上做并 commit 到 main**（步骤 2C）：这两份是项目级 baseline 不是 req 级，进 main 是语义正确；worktree 在步骤 4 从 main 拉自动带上
- **attachments trigger 0/1 改成内存 list `PENDING_ATTACHMENTS`**：步骤 3.5 仅做轻量预检（路径存在 + sensitive + size），实际 cp + register 推到步骤 4B batch 执行（worktree 创建后用 `copy_attachment` 走完整 helper 路径）
- **attachments trigger 2 砍**：worktree 还没建无 cp 目标；PM 想绕 chat 直接 cp → 等步骤 5 handoff 后在 worktree 新对话里做（由 stage-gate 后续 stage 入口 attachments trigger 兜底）
- **步骤 4 原子操作**：4A 拉 worktree → 4B batch cp attachments → 4C 写 brief.md（含引用 section）→ 4D 一次 commit；全程用 `git -C <worktree>` 不切 cwd，任一子步失败 fail-loud + 让 PM 手动 `git worktree remove` 回滚
- **二确门话术更新**：去掉「绝对路径行」（此时 brief.md 还没落盘）；新加「brief 草稿块」展示在 chat 里
- **commit 范围契约更强**：4D commit pathspec 限于本 req 目录（brief.md / .req-meta.json / tasks/ / attachments/）；`docs/PROJECT.md` / `docs/DESIGN.md` 已在步骤 2C 单独 commit 到 main 不在 4D 范围
- **handoff 内容不变**：PM 仍在新窗口手动 `cd <worktree>` + 起新 claude + 跑 `/pmai-req-stage-gate`

**测试**：

- `tests/test-attachments-helper.sh` 「new-req commit pathspec 含 attachments/」断言改为匹配新契约（attachments 永远在 4D commit 里，不再「触发时一并 commit」prose）—— 16/16 pass
- `tests/test-new-req-no-arg-prompt.sh` 4/4 / `tests/test-no-duplicate-questioning.sh` 4/4 / `tests/test-banner-label.sh` 10/10 / `tests/test-stage-source-helper.sh` 13/13 / `tests/test-tthw-smoke.sh` 2/2 全过
- `test-req-num-resolver.sh` 10/10 不破

**影响**：

- 消费仓 PM 跑 `/pmai-new-req` 时主对话**全程**主仓 main，PM `git status` 主仓永远 clean，brief 在 chat 看得见；二确通过 → handoff 块出现 → PM **自己** `cd` 切窗口。`AI 切了分支` 这个体验破绽消除
- INVARIANTS I-AD5 / I-DC1（dispatch 前 working tree 必须 clean）仍由步骤 4D commit 保证
- mental model 跟老仓（`pm-ai-workflow-template`）对齐：`docs/` 工作在 main，worktree 仅用作隔离

---

### 2026-05-27 — fix(init-project): 三层修复（黑话清理 + 路径推断默认值 + 资料档分流接住 PM 决定）

**触发**：PM 在新消费仓试用 `/pmai-init-project`，三层缺陷连环暴露 ——

1. AI chat 输出"然后做 brownfield 检测，再问背景和 intent" —— 工程黑话（`brownfield` / `intent` / `gate`）直接吐给 PM
2. AI 让 PM 从空白手敲落地路径（绝对路径），不主动用 `dirname(pwd)` 推默认值
3. 闸门检测目录已存在/含 .git/非空就硬拒，但 PM 明确说「就是这个路径，文件夹给你准备的」（目录里只有 3 个 ChatGPT 对话导出 + .DS_Store，非 codebase）—— 违反 [[feedback_pm_decision_is_binding_contract]]：PM 已拍 → AI 应该接住

**根因**：
- 黑话源头：`skills/init-project/SKILL.md` ASCII 流程图行 21 `name → path → [brownfield gate] → background → intent` + 阶段 A 标题 + 5 步顺序文字（AI 照念给 PM）
- 闸门设计缺陷：`init-project.sh` line 119-123 + skill step 3 不区分「真 codebase（要走 audit）」vs「资料档（PM 提前放的笔记/导出/PDF）」，一刀切拒

**改动**（PM 视角）：

- **黑话清理**：`skills/init-project/SKILL.md`
  - ASCII 流程图阶段 A 行换中文：「项目名 → 落地路径 → 已有内容判断 → 一句话背景 → 项目类型」
  - 阶段 A 标题：「参数收集 + brownfield 检测」→「参数收集（含已有内容判断）」
  - Rules 段加「PM-facing 输出禁词」表格（brownfield/greenfield/intent/project-intent/gate/闸门）+ PM 视角替代词映射；SKILL.md 内部段落（设计文档准确性）保留 brownfield 概念词
  - 失败兜底速查表重写：原「brownfield 检测命中」拆成 step 3a（codebase 硬拒）+ step 3b PM 三选三档
- **路径推断默认值**（自适应）：阶段 A step 2 判断 cwd 是否生成器仓（含 `skills/init-project/SKILL.md`）—— 是 → 推 `dirname(pwd)/<name>` 兄弟目录（老模式）；否 → 推 `pwd` 本身（v1.1 PM 在任意 cwd 启 claude 心智：「我在哪 init 就在哪」）。AskUser 二选 ① 用推断 ② 改别的
- **阶段 B 脚本路径走 `$PMAI_HOME` 绝对路径**：v1.1 PM 在任意 cwd 调 skill 都行（不再依赖 cwd = 生成器仓根）；fallback 到 `$(pwd)/scripts/init-project.sh` 兼容老模式
- **闸门：AI 主动诊断 + PM 一拍即可**（PM 同日第二轮反馈：「3a 代码标志清单写死永远不全 + 3b 三选 ①『挪到 docs/资料/』框架预设侵犯 PM 自主组织」→ 整个机制是 AI 装懂事；新方向「我已经在项目空间中了，你就直接看看当前目录情况，看看怎么初始化，怎么归档」）。step 3 重写：
  - **3.1** AI `ls -lAh` cwd + git log（如是 repo）
  - **3.2** AI 逐条标注（推测用途 / 类型 / 默认处置 —— 系统噪音 / 已有 git / 工具配置 / 文档 / 资料-导出 / 源码 / 已有 PMAI framework 七类）
  - **3.3** AI 给完整方案（结构化 4 部分：当前位置 / 内容 / 判断 / 方案逐条 source→target）
  - **3.4** PM AskUser 二选「① 走方案 / ② 我要改（自由 chat 反馈具体哪条调，AI 调完回 3.3 再确认，可循环）」
  - **3.5** ① → AI 执行归档 mv + 调脚本 `--allow-existing`
  - 退化捷径：cwd 完全空 / 仅 `.DS_Store` → 跳过 3.3/3.4 直接 init
  - **codebase / 已 init 项目 不硬 gate**：3.3 方案里**优先推荐** `/pmai-codebase-audit`（有源码）或 `/pmai-project-solution`（已有 PMAI 元数据），但 PM 坚持 init 也接住（[[feedback_pm_decision_is_binding_contract]]：init 不删代码 + 可逆）
- **`init-project.sh` 加 `--allow-existing` flag**：位置无关 flag 扫描；命中后跳过「目录已存在硬拒」line 119-123，复用现有目录 + git init 后 `git add -A` 把现有资料 add 进首 commit。skill 阶段 A step 3.5 PM 拍方案后由 AI 加上 flag 调用脚本

**测试**：

- `tests/test-brownfield-detect.sh` 3 → 5 case：T3 改语义断言（AI 诊断接口 + audit 引导 + `--allow-existing` flag + 不硬 gate 接口约定），不再依赖 `brownfield` / `两层都拦` 字眼；新增 T4（空目录 `--allow-existing` 接住）+ T5（资料目录 `--allow-existing` 接住 + 资料进首 commit）。本地 5/5 绿
- `tests/test-init-project.sh` 3/3 不破坏

**影响**：

- 消费仓 PM 跑 `/pmai-init-project` 时 chat 输出不再出现 `brownfield` / `intent` 等工程黑话；路径推断免敲；目录有内容 → AI 主动 ls + 出方案 + PM 一拍即可（不再被 AI 列三选菜单装懂事）
- `init-project.sh` 默认行为不变（位置参数兼容；不加 flag 仍拒已存在）；新 flag 只通过 skill 经 PM 拍板调用
- memory `feedback_pm_chat_no_engineering_jargon` 词典 A 加 `brownfield` / `greenfield` / `intent` / `project-intent` / `gate` / `闸门`，2026-05-27 两轮反馈案例入档

---

### 2026-05-27 — fix(req-num-resolver): max=008/009 时 `$((...))` 按 octal 解析报错，强制 base-10

**触发**：ExampleConsumerApp PM 在 closed/req-008 之后跑 `/pmai-new-req`，helper 报 `008: value too great for base (error token is "008")` 直接挂掉；PM 手动判断编号是 009 继续。

**根因**：`scripts/_lib/req-num-resolver.sh:51` 算 next 编号用 `$((${max:-0} + 1))`，bash arithmetic 把前导 0 的数当 octal，008/009 不是合法 octal（octal 只到 0-7）。closed/active/branch 任一来源的 max 落到 008/009 都会炸；010 之后没事（不再前导 0）。

**改动**：

- `scripts/_lib/req-num-resolver.sh:next_req_num` 改 `$((10#${max:-0} + 1))` 强制 base-10 解析；加一行 inline comment 说明 octal 坑。
- `tests/test-req-num-resolver.sh` 加 2 个回归 case：`closed=008 → next=009`、`branch=req-009 → next=010`，挂到 runner 列表里。原 10 case 测试覆盖 001-007 + 010，唯独漏了 008/009 这两个 octal 边界 —— 这是 bug 漏出去的原因。

**测试**：suite 8 → 10 case 全过。

---

### 2026-05-27 — fix(prefix): 所有 skill 加 `pmai-` 前缀 — frontmatter / 文档 / 测试三层统一

PM 发现 ExampleConsumerApp 里 slash 列表显示的命令**不带前缀**（`/task-execute` 而不是 `/pmai-task-execute`），戳穿了之前对前缀机制的误解：Claude Code 的 slash 名取自 SKILL.md frontmatter `name:` 字段，**不是目录名**。`pmai-install` 把目录名加 `pmai-` 前缀这层对暴露给 PM 的 slash 名零作用——目录前缀白加了（除了 pmai-upgrade 因为 frontmatter 也写了 pmai-upgrade 才真生效）。对照 gstack：每个 SKILL.md frontmatter 都带 `gstack-` 前缀，目录 + frontmatter 双层加，slash 名真带前缀；PMAI 是「目录加前缀，frontmatter 不加」的半成品。

**改动**：

- **22 个 SKILL.md frontmatter `name:` 字段加 `pmai-` 前缀**：cancel-req / close-req / close-task / codebase-audit / doc-update / implementation-design / init-project / new-req / prd-writing / project-solution / publish-to-lark / quick-fix / req-analysis / req-stage-gate / skill-improve / task-confirm / task-execute / task-plan / task-spec / task-status / task-submit / task-verify。pmai-upgrade 已带前缀跳过。
- **1050 处文档 slash 引用同步加前缀**：skills/ + templates/ + scripts/ + docs/ + CLAUDE.md + RUNTIME.md + CHANGELOG.md + README.md 下所有 `/<skill>` → `/pmai-<skill>`。用 perl 带 lookbehind `(?<![/.\w])/<skill>\b` 安全替换，避开路径引用（`skills/task-execute/`）和复合名（`task-execute-something`）。
- **43 处测试期望字符串同步加前缀**：tests/ 下 .sh / .md / .py 文件里 hardcode 的 slash 名。
- gstack 的命令（`/office-hours` / `/qa` / `/review` 等）不动，保留原前缀。

**PM 体验变化**（重要）：
- 旧：`/task-execute` → 新：`/pmai-task-execute`
- 旧：`/close-task` → 新：`/pmai-build-close-task`
- 旧：`/new-req` → 新：`/pmai-new-req`
- 旧：`/req-stage-gate` → 新：`/pmai-req-stage-gate`
- ...（22 个全部加前缀）

**消费仓历史数据不 backfill**：ExampleConsumerApp 等业务仓里已写入的 task md / req md 里仍是 `/task-execute` 等不带前缀的命令引用——这是历史记录，不强制改写。PM 未来在 IDE 输入时用带前缀的新名（`/pmai-task-execute`），生效来自 ~/.pmai 升级 + Claude Code 重新读 frontmatter。

**测试**：全测 541 / 0 全过；6 个 suite 中间因测试期望字符串 hardcode 旧名暂时失败，同步把 tests/ 替换后恢复 541 / 0。

**Why 这次改动算 P0 而不是技术债**：
- 防冲突是前缀的本来目的，frontmatter 不加 = 这层设计废了；目录加前缀就是装饰
- 文档 vs IDE slash 名 vs LLM system reminder 三处现在终于对齐：都是带前缀的
- 跟 gstack / lark 的命名模式一致，避免"半成品"观感
- AI 调用稳定性提升：LLM 看 system reminder 是 `pmai-task-execute`，文档里写 `/pmai-task-execute`，两边对得上，不需要"脑内 resolve"

### 2026-05-27 — fix(pmai-upgrade): 升级原子化 — dirty stash + trap 回滚 + --local mv swap + 升完跑 doctor

PM 提"升级方案不靠谱"——担心两件事：跑一半挂了半新半旧，PM 改了 `~/.pmai` 被 reset --hard 冲掉。审完 `gstack-upgrade` / `gsd install.js`，照搬 gstack 的兜底套路改 `bin/pmai-upgrade`（266→376 行）。

**改动**：

- **A 全局模式 dirty 自动 stash**：升级前 `git status --porcelain` 不空 → `git stash push -u` 自动救 PM 在 `~/.pmai` 的本地改动；末尾告知 `cd ~/.pmai && git stash pop` 恢复路径
- **B 全局模式 trap ERR 自动回滚**：升级前记录 `OLD_HEAD` + 装 `trap global_rollback ERR`；fetch / checkout / symlink / doctor 任何一步挂 → `git reset --hard $OLD_HEAD` + 按 OLD_HEAD 重建 symlink + 提示 stash pop；`ROLLBACK_DONE` flag 防重入
- **D --local 模式 staging + mv swap**：原来的 `rm -rf $LOCAL/.claude/skills && cp -R` 不原子，挂中间半新半旧；改成先 cp 到 `*.new` staging dir → staging 自检（skill 数 < 22 视为失败）→ 原 `mv` 成 `*.bak` → staging `mv` 到正式位 → 成功清 .bak；失败 trap 把 .bak 推回原位 + 清 .new
- **E 升完跑 pmai-doctor 自检**：全局模式末尾跑 `pmai-doctor`，FAIL 触发 B 的回滚（WARN 不触发）；--local 模式因为没 `~/.pmai` 用 lite check（staging 阶段 skill 数 ≥ 22）
- 全局 `set -Eeuo pipefail`（加 `-E` 让 trap 在函数 / subshell 内也生效）

**兼容性**：纯增量保护层，PM 跑 `pmai upgrade` 命令、flag 全部不变（`--stable` / `--to vX` / `--local` / `--no-whats-new` 行为同前）。回滚是失败兜底，不改成功路径。

**未做（明确放弃）**：
- C symlink staging swap：B 的 trap 已 cover symlink 半重建场景；C 引入 staging 目录会让 doctor / status 等下游学会忽略，复杂度跳一档但只防"trap 自己挂"的低概率场景，ROI 不值
- migration 脚本机制（gstack `v{VER}.sh` pattern）：当前还没真实 breaking change 案例，先不引入框架

**测试**：bash -n 通过；clean 状态跑 `pmai upgrade` 跑通 doctor + 24 symlink；造 dirty 跑 `pmai upgrade` stash + 升级 + 末尾提示 pop 都对。trap 回滚路径不实际制造 doctor fail 测（会动 `~/.claude/skills` 真 symlink，风险大于收益）—— 三个 rollback 动作（reset --hard / rebuild_symlinks / stash pop 提示）单独逻辑都验过。

### 2026-05-27 — refactor(templates): 修正 PROJECT/ROADMAP/lark-publish 位置 — 按 GSD pattern 扁平化

上轮 refactor 把 lark-publish.json.tmpl 移到 `skills/publish-to-lark/templates/`，PM 反馈：业务实例配置（PM cp + 填 token）不该绑死单个 skill。参照 GSD（`get-shit-done/templates/` 把 `config.json` 放顶层 + workflow 内只放周期产物 checkpoint/context）的 pattern 修正：

- `templates/lark-publish.json.tmpl` 回 templates/ 根（业务实例配置，跟 GSD `config.json` 顶层一致；不搞 `templates/instances/` 子目录，扁平化）
- 同步更新 `skills/publish-to-lark/SKILL.md` + `scripts/init-project.sh` 路径
- `init-project.sh` 注释更新：主 loop case 把 lark-publish 也归入「不走占位符替换」跳过分支（下方 f3 段独立 cp）

**判断原则总结**（GSD pattern 借鉴）：
- skill 自包含 templates/：仅装"该 skill 周期内一次性产物的模板"（如 task-plan / req-prd / implementation-design / codebase-audit / module）
- 框架根 templates/：项目级长期文档（PROJECT / ROADMAP / CLAUDE / PRODUCT-RULES）+ 多 skill 共用（task）+ 业务实例配置（lark-publish）+ 纯 init scaffold（settings / gitignore / 等）

### 2026-05-27 — refactor(templates): skill 自包含 — 6 个 skill 独占 .tmpl 移进 skills/<skill>/templates/

PM 实测发现 `templates/lark-publish.json.tmpl` 跟 `skills/publish-to-lark/` 分裂在两个目录，问"skill 依赖为啥不和 skill 放一起"。Audit 仓内每个 .tmpl 被谁引用后，把 skill 独占的 6 个移进各自 skill 目录，剩下的 8 个保留（init scaffold + 多 skill 共用）。

**移动**：
- `templates/codebase-audit.md.tmpl` → `skills/codebase-audit/templates/`
- `templates/module.md.tmpl` → `skills/codebase-audit/templates/`
- `templates/implementation-design.md.tmpl` → `skills/implementation-design/templates/`
- `templates/req-prd.md.tmpl` → `skills/prd-writing/templates/`
- `templates/task-plan.md.tmpl` → `skills/task-plan/templates/`
- `templates/lark-publish.json.tmpl` → `skills/publish-to-lark/templates/`

**保留 templates/**（不移）：
- 纯 init scaffold：CLAUDE.md / PRODUCT-RULES / PROJECT / ROADMAP / modules-INDEX / pm-workflow.config / gitignore / settings.json
- 多 skill 共用：task.md.tmpl（task-spec + task-confirm + init-project + state_test 4 触点）

**改动**：
- 5 个 SKILL.md 路径引用从 `$PMAI_HOME/templates/X.tmpl` → `$PMAI_HOME/skills/<skill>/templates/X.tmpl`
- `scripts/init-project.sh` 主 loop 移除 6 个 .tmpl 的 `continue` 分支；新增独立段 cp `skills/publish-to-lark/templates/lark-publish.json.tmpl` → consumer `templates/`（业务实例配置，PM 后续 cp + 填 token 必须留实体）
- 4 个 test 文件路径同步更新（test-implementation-design / test-task-spec / test-task-plan / test-speed-mode）

**收益**：
- skill 自包含：删 skill 时连带 .tmpl 一并删，无孤儿
- 看 skill 时一眼能看到它用的所有资源（SKILL.md + references/ + templates/）
- 框架根 `templates/` 收敛到"消费仓 scaffold 模板"语义

**测试**：541/0 全绿。

### 2026-05-27 — feat(close-task / close-req): 兜底清孤儿 worktree（按 task/req 记录定向）

PM 实测 ExampleConsumerApp 攒了 17 个 worktree 物理残留占 261 MB —— 历史 close 流程在 git worktree remove 失败后没清干净（早期版本无 rm -rf fallback / PM 中途 Ctrl+C 等）；当前 close 单 task 即使有 fallback 也只清当前 task，不扫历史残留。

**改动**：

- `scripts/_lib/worktree.sh` 加 `cleanup_stale_worktrees <repo_root>` 函数 + 内部 `_stale_worktree_check_one` helper。**按 SOT 定向**（不无差别扫 `.worktrees/*`）：
  - `git worktree prune` 先清 git 索引死引用
  - 枚举 `requirements/{active,closed}/*/tasks/task-*.md` + `requirements/<state>/<req-stem>`，对每条记录推导 `${PM_AI_WORKTREE_BASE:-<repo>/.worktrees}/<stem>` 路径
  - 路径存在 + git 不认 + 不是当前 cwd → `rm -rf`
- `scripts/close-task.sh` 步骤 8 末尾调用 `cleanup_stale_worktrees`
- `scripts/close-req.sh` Step 4 末尾调用同函数

**护栏**：
- 只清 SOT 推导的 path，不动随机目录（验证用例 `random-not-a-task` 保留 ✓）
- 不删 cwd 在内的目录（不删自己脚下）
- 跳过 live worktree（`git worktree list` 仍认的）
- 跳过 `*.engineering.md`（不是 task 本体）

**已知 trade-off**：
- 只 cover `PM_AI_WORKTREE_BASE` 约定路径（99% case）；PM 手动 mv 过 worktree 到非约定位置不会被自动清，但也安全
- quick-fix `tmp-quick-*` worktree 不在 task/req 记录里，本来就 self-cleanup，不处理

**端到端**：mktemp 建 fake 仓 + 2 个 task 记录 + 3 个 .worktrees/ 物理目录（2 个匹配 task / 1 个不匹配），跑 cleanup → 2 个孤儿清掉，random 保留 ✓。全测 541/0。

**影响**：业务仓后续任意 close-task / close-req 触发时自动顺手清掉历史漏清残留；今天的 17 个残留在下次 close 或手动 `source ~/.pmai/scripts/_lib/worktree.sh && cleanup_stale_worktrees <consumer>` 即清。

### 2026-05-27 — fix(pmai-upgrade): fetch 按 MODE 分流 + 加 timeout（修网络慢卡死 4 分钟）

PM 实测 `pmai upgrade` 卡 4 分钟，根因 `git fetch origin --tags` 在 SSH 慢的网络环境拉所有 tag 引用慢。本次根因修：

- **default `main` 模式**：改 `git fetch origin main`（只 main 分支，不 `--tags`），快 10× —— main 模式根本不需要 tag 信息
- **`--stable` / `--to`**：仍 `--tags`（必需）但加 60s timeout
- **`--local` 模式 clone**：加 120s timeout
- 所有 fetch / clone 超时清晰报错"网络 / SSH 不通"，不再无声卡死；失败 exit 1 不掩盖问题

**影响**：业务仓 PM 跑 `pmai upgrade` 在国内网络环境从 4 分钟 → 数秒；`/pmai-upgrade` skill 调它也同样受益。`--stable` / `--to` 仍走 tag fetch（必需），最坏 60s 超时退出。

### 2026-05-27 — fix(skill-preamble + check-branch) + ci: 2 个生产真 bug 直修 + 4 stale test 同步 + GitHub Actions CI

`/devex-review` 后跑全测发现 6 个 fail，里面 **2 个不是 stale 测试，是生产环境也坏的真 bug**：

**真 bug 1 — `scripts/skill-preamble.sh:165`**：`_state_py="$_PREAMBLE_DIR/_lib/state.py"` 中 `_PREAMBLE_DIR` **从未被赋值**（脚本里只此一处用），拼出来是 `/_lib/state.py`，python3 调用必失败被 `|| true` 吞掉。后果：`ACTIVE_TASK` / `ACTIVE_TASK_STATUS` 永远算不出值，skill preamble 输出永远缺这两行，依赖 ACTIVE_TASK 的 skill 行为退化到「没活跃 task」分支。修：改 `$PMAI_HOME/scripts/_lib/state.py`（PMAI_HOME 头部已算）。

**真 bug 2 — `scripts/check-branch.sh:342`**：`python3 "${MAIN_REPO_ROOT}/$HOME/.pmai/scripts/task-transition.py"` 把两个绝对路径相拼（`/tmp/foo` + `$HOME/.pmai/...`）= `/tmp/foo/$HOME/.pmai/...`，文件**永远不存在**，python3 必失败 → `TASK_STATUS` 永远空 → I-CB10 gate 永远报「未知」→ task worktree 任何代码写入都被 deny。修：改 `${PMAI_HOME:-$HOME/.pmai}/scripts/task-transition.py`。

**stale 测试同步**（4 处，断言比代码改动慢半拍）：

- `tests/test-speed-mode.sh` T13：grep 字面 `status-view.py --stage6-entry` 匹配不到 SKILL.md 里 `status-view.py" --stage6-entry`（双引号包路径）→ 改通配正则
- `tests/test-init-project.sh` T1+T2：旧 cp 模式守护 → I-mini（消费仓 0 framework）后该死。重写为反向回归守护：T1 验 init-project.sh 不含 `cp -R.*SKILL_DIR`，T2 验生成项目 `.claude/` 不含 `skills/scripts/agents/templates/`
- `tests/test-tthw-smoke.sh` T2：调 `python3 .claude/scripts/status-view.py`，I-mini 消费仓没这个路径 → 改 framework `$REPO_ROOT/scripts/status-view.py`

**配 CI（`.github/workflows/tests.yml`）**：push 到 main / PR 自动跑 `bash tests/run-all.sh`，ubuntu-latest + python 3.10，timeout 10 min。RUNTIME 漂掉的「525/2 vs 实际 535/6」就是无 CI 的代价 —— 现在制度化。

**测试基线**：525/2（RUNTIME 旧）→ 535/6（baseline 真相）→ **541/0**（全过）。

### 2026-05-27 — feat(pmai-upgrade + skill): `--local <dir>` 升级模式（团队仓不再缺升级入口）

借鉴 GSD `get-shit-done-cc` 的双模式升级路线（global + local 都支持），补 PMAI 之前只支持全局升级的缺口。

**触发**：PM 用 `--local` 装在团队仓后无法用 `/pmai-upgrade` skill（只支持全局 `~/.pmai/`），团队仓升级要手动重跑 `install.sh --local .` —— 没 AI 智能 What's New 摘要。

**改动**：

- `bin/pmai-upgrade` 加 `--local <dir>` flag：mktemp 重克隆源 → 按 `--stable`/`--to` checkout → 覆盖 `<dir>/.claude/{scripts,skills,agents}/` 实体副本 + 拷 `CHANGELOG.md` + 更新 `.pmai-version` + 写 JUST_UPGRADED marker + 末尾打印 `git add/commit/push` 提示
- `bin/pmai` dispatcher help 加 `--local <dir>` 标志说明 + 团队仓 example
- `skills/pmai-upgrade/SKILL.md` v1.1.0：Step 0 加 mode 自动检测（cwd 含 `.claude/.pmai-version` → local mode；否则 ~/.pmai/.git → global mode），Step 1 探远程用 `git ls-remote`（local 模式无本地副本可 fetch），Step 3 按 mode 分流升级命令，Step 4 CHANGELOG 路径按 mode 切换
- frontmatter `version: 1.0.0 → 1.1.0`

**端到端 smoke test 通过**：
- TESTDIR + 假 `.pmai-version 0.0.1-test` → `pmai-upgrade --local TESTDIR --no-whats-new` → 重克隆 v0.2.1 + 24 skill 实体副本 + CHANGELOG 拷贝 + marker 写入
- 错误分支：非 install 目录、空 dir 参数、不存在目录 都有清晰报错
- 双前缀 bug 不复现（install_skills_copy 函数复用 bin/pmai-install 的 case 三分支）

**影响**：团队仓 PM 可在 cwd 内跑 `/pmai-upgrade`，AI 自动按 `--local` 模式升 + 给 commit/push 指引；全局模式行为完全不变（向后兼容）。

### 2026-05-27 — fix(bin/pmai*+README): /devex-review 抓出的 3 个 install/help UX bug 直修

`/devex-review` 实测命中 3 个新摩擦点，本次一并修：

- **`README §安装` PATH 教程失效** — 旧文案教用户加开发仓 `bin/` 到 PATH，但开发仓位置随 clone 路径变化、且与 `pmai install` 实际落地的 `~/.pmai/` 互相分裂。改为：clone 到 `/tmp/pmai-src` 临时位置 → `bash /tmp/pmai-src/bin/pmai install` 绝对路径调 → install 末尾给 oneshot 把 `~/.pmai/bin` 加进 PATH（稳定路径，不绑开发仓位置）。
- **`bin/pmai-install` 装完末尾加 PATH 检测段** — 探 `$SHELL`（zsh/bash/其他）+ 探 rc 文件路径，没装过就 echo `📌 一步加 PATH` oneshot（不自动写 rc，避免破坏用户配置）；已装过给 `ℹ️ 已含 export — 开新窗口 / source 即可`。
- **`bin/pmai` 主菜单漏列 `migrate` / `whats-new`** — case 分支早就 route 了这两个，但 `pmai --help` usage 文本没列；新用户用 `pmai migrate --help` 才能试出来。补两行说明。
- **`bin/pmai-status` 没装时仍显示「22 symlinks」自相矛盾** — 顶部说 `❌ not installed`、下面却列 22 个 skill = 误导。改为 `INSTALLED=0` 时 symlink 段标 `⚠️ 悬空（指向不存在的 ~/.pmai/；pmai install 后才生效）` 并跳过具体 skill 名单（悬空名单意义不大）。
- 顺手：`bin/pmai-status` 中文 echo 行的 `$PMAI_HOME` 改 `${PMAI_HOME}`，避开 bash `$VAR紧跟中文` unbound 边界 bug（与 `feedback_bash_var_chinese_boundary.md` 同型）。

**影响**：纯 user-facing UX 修复，不动框架资产同步面（bin/ 不进消费仓）；测试基线 **535/6**（vs baseline **535/6**，0 回归）。

### 2026-05-27 — feat(install.sh): curl 一行安装入口（gstack-style oneliner）

- 新增 `install.sh` 在 repo 根：依赖检查 + SSH 优先 / HTTPS fallback git clone + 跑 `bin/pmai install [args]` + 清临时容器
- 调用方式：
  ```
  curl -fsSL https://raw.githubusercontent.com/YYG501/PMAI_Workflow/main/install.sh | bash
  curl -fsSL ... | bash -s -- --local /path  # 透传 --local 给 pmai install
  ```
- SSH 失败时自动 export `PMAI_REMOTE=https://...` 让 `pmai install` 内部 git clone 也走 HTTPS（新机器没配 SSH key 时仍可装；私有仓 HTTPS 需要 token）
- README「安装」段重写：curl oneliner 作主推荐 + 手工模式保留 + 两种安装模式对照表（default / --local 跨机器差异）
- 本地 round-trip 验证：装 v0.2.1 + 24 skill entries，临时容器自动清

### 2026-05-27 — feat(pmai-upgrade skill): standalone 模式 — PM 在 Claude Code 内 /pmai-upgrade 含 AI 智能摘要

借鉴 gstack-upgrade SKILL.md，给 PMAI 升级流程加 skill 入口（PMAI 阶段 1 gstack 借鉴扩展，B-简版）：

- 新增 `skills/pmai-upgrade/SKILL.md`：standalone 模式 6 步 — Step 0 解析当前安装 / Step 1 探查远程 / Step 2 AskUser 4 选项（升级 main / stable tag / 锁版本 / 暂缓 1 天/1 周/永远）/ Step 3 调 bin/pmai-upgrade --no-whats-new / Step 4 读 CHANGELOG OLD..NEW + AI 5-7 bullet 智能摘要（按主题归类，跳纯重构 commit）/ Step 5 清 marker / Step 6 继续 PM 原任务
- `bin/pmai-upgrade` 加 `--no-whats-new` flag：跳过 bin/pmai-whats-new 自动 dump（skill 接管 What's New 时用）
- frontmatter：`version: 1.0.0` / `triggers: 升级 PMAI / 升级框架 / pmai upgrade / upgrade pmai` / `allowed-tools: Bash + Read + AskUserQuestion`

**两个调用入口共存**：
- Shell（脚本化 / cron）：`pmai upgrade` — 保留原逻辑，bin/pmai-upgrade 自动调 pmai-whats-new dump
- Claude Code（PM 日常）：`/pmai-upgrade` — skill 接管，调 bin/ 但跳 dump，AI 智能摘要

**未实现（B-完整 scope，本次不做）**：Inline 模式（其他 skill preamble 检测 UPGRADE_AVAILABLE 时自动 invoke pmai-upgrade flow）。PM 单人场景 standalone 够用；多人团队 / 升级强提醒场景未来补。

### 2026-05-27 — fix(close-task / gitignore.tmpl): 清 task verify 运行时元数据

- `scripts/close-task.sh` §6.5 加清理段：task worktree remove 后，**还**扫一遍 main / req worktree 内的 `.pm-workflow/tasks/<task>/verify/`，删 `dev-server.info` + `_dev-server.log`（PID/PORT 元数据，task close 后无意义）；保留 report.md / flow-*.png / _plan.md 审计资产
- `templates/gitignore.tmpl` 加 `**/dev-server.info` + `**/_dev-server.log` ignore，新装消费仓未来不会 untracked 残留
- 根因：现役 close-task 只清 task worktree 内 verify/（worktree remove 顺带），不清 main/req worktree 副本（PM 在 main cwd 跑过 task-verify 时写）；example-consumer-app task-002 实测撞过

### 2026-05-27 — feat(pmai-migrate): vendored → I-mini 一键迁移命令

- 新 `bin/pmai-migrate <consumer-dir> [--dry-run] [--force]`
- 9 步动作：探测 vendored 模式 → git rm 4 块实体 → 清 templates runtime → 重写 settings.json → 重装 pre-commit → 删 .framework-sync-state.json
- working tree 检查只限 framework 路径（业务路径 dirty/untracked 不阻塞）
- step 6 cp settings.json 后立即 git add（防 commit 漏 — example-consumer-app 实测撞过补 fix）
- example-consumer-app 实测：126 文件清掉 framework 副本，skill-preamble 跑通

### 2026-05-27 — feat(pmai 阶段 1): JUST_UPGRADED + What's New / update-check 缓存 / uninstall preview

**借鉴 gstack 三个机制**（详 transcript "gstack 关键机制借鉴评估"）：

1. **JUST_UPGRADED marker + Show What's New**
   - `pmai-upgrade` 成功后写 `~/.pmai-state/just-upgraded-from` 存老版号 + 清 `last-update-check` / `update-snoozed`
   - 立即调 `pmai-whats-new` 读 `CHANGELOG.md` 「未发布」段打印（含"v{TO} — upgraded from v{FROM}" 头 + 80 行限）
   - 新增 `bin/pmai-whats-new`：独立脚本，可手动 `pmai whats-new` 或 `--from VER --to VER` 显式跑；marker 读完即清
   - PM 体感：升级完直接看到 changelog，不再蒙在鼓里

2. **update-check 24h 缓存 + snooze**
   - `pmai-update-check` 加 `~/.pmai-state/last-update-check` 时间戳；24h 内 silent skip 不打 GitHub
   - `--force` flag 跳缓存
   - `~/.pmai-state/update-snoozed` 用户暂缓内（未来 1.1 改进时填）
   - smoke：首次跑写 cache；24h 内重跑 30ms 内退出
   - 修了 set -o pipefail + grep no-match 让 pipeline exit 的 bug（用 `{ ... ; } 2>/dev/null || true` 子壳隔离）

3. **uninstall preview + --keep-state**
   - 跑前打印详细 clean-up 清单：~/.pmai/ 版本 + git head + 大小，~/.pmai-state/ 内容列表，symlink 数量 + 前 5 个名字
   - `--keep-state` 保留 `~/.pmai-state/`（重装后 PM 偏好 / cache 不丢）
   - `--force` 行为不变（跳 [y/N] 但 preview 仍打）
   - 跟 gstack-uninstall 安全机制对齐

**新增 state 目录**：`~/.pmai-state/`
- `just-upgraded-from`：刚升级的老版号 marker
- `last-update-check`：24h cache 时间戳
- `update-snoozed`：用户暂缓时间戳
- 未来：`config.yaml`（阶段 2 #4 加 pmai-config 体系）

**VERSION**：0.2.0 → 0.2.1

**Non-goals**（阶段 2/3 待做）：
- VERSION migrations（gstack 机制 #1）
- pmai-config get/set/list 体系（gstack 机制 #4）
- install-type detection（机制 #6）
- vendored copy → team_mode 迁移（机制 #7）—— 跟 T3/T5 example-consumer-app 迁移绑定

### 2026-05-27 — feat(I-mini): 消费仓 0 framework + skill 全走 \$PMAI_HOME（跨机器 clone 0 setup）

**目标**：照搬 gstack 模型——消费仓内**不放任何 framework 资产**（scripts/skills/agents/templates/hooks），skill 内部脚本调用全用 `$PMAI_HOME/scripts/...` 绝对路径；任何机器 clone 消费仓 + `pmai install` 后立即可用，0 setup。详 `$HOME/.claude/plans/tingly-bouncing-rocket.md`。

**问题根因（修复前）**：v1.1 default symlink 模式 symlink target 是绝对路径硬编码 `/Users/<安装时用户名>/.pmai/`。git tracked symlink target 字符串跨 clone 不变 → 消费仓 push 后别的机器/用户 clone 全部 dangling。

**改动汇总**（48 文件 / ~150 处替换）：
- `scripts/skill-preamble.sh`：顶部加 `PMAI_HOME` 解析（env → self_dir 推导 → ~/.pmai fallback → 报错）+ self check
- `scripts/init-project.sh`：删 5 块 symlink 段（scripts/skills/agents/templates/hooks 不再进消费仓）；只保留业务实体（CLAUDE.md / docs/PROJECT.md / .gitignore / settings.json / lark-publish.json.tmpl 业务实例）
- `scripts/close-task.sh`：framework 互调 4 处 `$REPO_ROOT/.claude/scripts/` → `$SCRIPT_DIR/`（用 BASH_SOURCE 推自身路径）
- `scripts/install-hooks.sh`：模板查找加 `$PMAI_HOME/templates/git-hooks/` 第 3 candidate（兼容 I-mini）
- `templates/settings.json.tmpl`：hook 路径 `bash .claude/scripts/check-branch.sh` → `bash "$HOME/.pmai/scripts/check-branch.sh"`，review-skill-guard 路径 `$CLAUDE_PROJECT_DIR/hooks/` → `$HOME/.pmai/hooks/`；permissions allow 同步改 `$HOME/.pmai/scripts/`
- `templates/git-hooks/pre-commit.tmpl`：顶部加 `PMAI_HOME` fallback 自检；3 处 `$REPO_ROOT/.claude/scripts/` → `$PMAI_HOME/scripts/`
- 22 个 SKILL.md ~88 处 `.claude/scripts/` / `$REPO_ROOT/.claude/scripts/` / `$REPO_ROOT/templates/` → `$PMAI_HOME/scripts/` 或 `$PMAI_HOME/templates/`
- `skills/task-execute/SKILL.md` + `executor-dispatch.md`：11 处 `$MAIN_REPO_ROOT/.claude/scripts/` → `$PMAI_HOME/scripts/`（Step B 漏 grep 补打）
- scripts/ + templates/ 内 ~48 处 prose / 错误提示 / 注释 `.claude/scripts/` → `$HOME/.pmai/scripts/`

**验证 6 smoke 全过**：消费仓物理结构 0 framework / `_lib.state + events` import / `status-view.py` 跑通 / 真 git commit + pre-commit hook 真跑（按当前 framework 逻辑拦 docs/notes2.md 错位 → 验证 `$PMAI_HOME/scripts/check-docs-toplevel.py` 解析正确）/ 跨位置 clone 后 source preamble 解析当前机器 PMAI_HOME / grep 残留 0。

**消费仓最终结构（init 后）**：
```
<consumer>/
├── .claude/settings.json          # 实体，hook 路径 $HOME/.pmai/...
├── .git/hooks/pre-commit           # 实体（install-hooks 装），顶部自检 PMAI_HOME
├── .gitignore CLAUDE.md            # 业务实体
├── docs/PROJECT.md DESIGN.md ROADMAP.md PRODUCT-RULES.md modules/ 归档/
├── requirements/active closed/  prototypes/  .runs/events/  .worktrees/  .pm-workflow/
├── templates/lark-publish.json.tmpl   # 唯一业务实例配置模板
└── (NO .claude/scripts / NO .claude/skills / NO .claude/agents / NO hooks/)
```

**Non-goals**（暂缓）：
- 老消费仓（example-consumer-app 等已自带 `.claude/` 副本）迁移 — PM 5/26 决议 T3/T5 暂缓
- `~/.pmai-state/projects/<slug>/` per-project state（I-full 范围）

### 2026-05-27 — fix(create-req-headless+CLAUDE.md): attachments 目录预建 + CLAUDE.md 文案纠正「现在就能用」

**触发**：DESIGN.md 缺口审计后 PM 反问「还有 attachment 呢」+「为什么是未来有」。盘点：`requirements/active/<req>/attachments/` 是 per-req 目录、由 `_lib/attachments.py:copy_attachment()` 第一次上传时 `mkdir(exist_ok=True)` 自建 —— 零 break，但 DX 不对称：同位置的 `tasks/_archived/` `create-req-headless.sh` 预建（IDE 一眼可见），attachments 不预建（PM 第一次起 req 时 IDE 看不到目录 → 不知道有这个机制）。叠加 CLAUDE.md 模板 line 219 文案把 attachments 描述成「（可选）」让 PM 误以为是「未来才有 / 可有可无」。

**改动**（PM 视角）：

- `scripts/create-req-headless.sh` 每个 req 预建 `attachments/.gitkeep`（跟 `tasks/_archived` 对称）—— IDE 一眼可见 attachments 目录存在
- `templates/CLAUDE.md.tmpl` 「文档位置」表 attachments 行重写：去掉「（可选）」，明确「**每个 req 默认可用**（new-req 时预建空目录）」+ 写清 PM 怎么用（chat 贴绝对路径 + 描述材料 → AI 自动归档登记，无需 PM 学路径操作）+ 指针到 `attachments-upload.md` 细节

**影响**：

- 新起 req：IDE 文件树立刻看到 `attachments/`（即使未上传任何文件）
- 老 req（之前已存在 attachments/ 但无 .gitkeep）：不动；下次 PM 上传时仍走 helper 自动 mkdir
- CLAUDE.md：PM 一眼知道这是「现在每个 req 都能用」的机制，不是「未来有」的可选功能

### 2026-05-27 — fix(codebase-audit+new-req): docs/DESIGN.md 不存在时兜底建空骨架（双保险）

**触发**：codebase-audit step 3.5 落地后做初始化缺口审计，找出 1 个真缺口 `docs/DESIGN.md`。138 处引用 / 是 stage 4 4A gap-check 硬依赖，但：greenfield + gstack 不可用 / brownfield / 已升级老项目 三种场景下文件根本不存在，且 `new-req` 步骤 3.6 原逻辑 `[ -f "$DESIGN_MD" ] && ! grep ...` 第一个条件 false 即 silent skip → stage 4 4A 跑 `grep "共享组件 inventory"` 隐性 break，PM 第一个 req 推不到 stage 5。

**根因**：3.6 兜底逻辑只覆盖「文件存在但缺 inventory 段」分支，「文件不存在」直接 silent skip 没建。

**改动**（PM 视角）：

- `skills/codebase-audit/SKILL.md` 加 **step 3.5.5 DESIGN.md inventory 段兜底**（**无条件**，独立于 step 3.5 PM [Y/N] 选择）：HAS_FILE × HAS_INVENTORY 二维状态矩阵 —— 都有 silent skip / 有文件缺段追加 inventory / 无文件建空骨架（含顶部状态行 + 提示 PM 跑 gstack `/design-consultation` 补视觉基线 8 段 + inventory 空段）。brownfield 接入时一次性兜底。
- `skills/new-req/SKILL.md` 步骤 3.6 加「HAS_FILE=false → 建空骨架」分支（同款写入逻辑），原「追加 inventory 段」分支保留。每 req 入口兜底 —— 任何遗漏的最后防线。
- `skills/codebase-audit/SKILL.md` 边界段更新：允许 step 3.5.5 写 `docs/DESIGN.md`；明确「不替 gstack 写视觉基线 8 段」硬约束（视觉基线由 PM 主动调 `/design-consultation`，本框架只兜 inventory 段 + 空骨架）。
- `skills/new-req/SKILL.md` 步骤 4.5 commit 范围扩展从「追加 inventory 段到 DESIGN.md」改成「追加 / 新建空骨架到 DESIGN.md」—— 覆盖新建分支。

**影响**：

- Greenfield + gstack 可用：行为不变（init C.5 仍由 gstack 建完整文件）
- Greenfield + gstack 不可用：第一个 req 入口 new-req 3.6 兜底建空骨架（不再 silent skip）
- Brownfield 接入：codebase-audit step 3.5.5 一次性兜底（推荐路径）；即使跳过仍由 new-req 3.6 兜底
- 已升级老项目（如消费仓 ExampleConsumerApp）：下一个 new-req 时 3.6 自动检测 + 兜底；不需要 PM 手动做任何事

### 2026-05-27 — feat(codebase-audit): step 3.5 modulespec 主规格骨架，brownfield 接入时一次性建好

**触发**：刚加完 close-req §1.5 step 2.5 稳定结构反查（事后兜底），PM 反问「为什么不在初始化时就建好」。盘点发现框架已有 greenfield / brownfield 分流（`/pmai-init-project` vs `/pmai-codebase-audit`），但**两条路径在 modulespec 上都漏了** —— 都只建 `docs/modules/` 空目录 + INDEX.md，从不主动建任何主规格文件。**老项目 IA 通常已稳定**（看代码就能识别模块边界），错过这个天然的 bootstrap 时机 → 之后每个 req close 都会被 §1.5 step 2.5 反复问「这个稳定结构要不要沉淀」。

**根因**：`/pmai-codebase-audit` 的 7 维度只覆盖技术栈 / 集成 / 架构 / 目录 / 约定 / 测试 / 隐患通用维度，**漏了「产品模块清单」这一维**，也没产 modulespec 骨架。

**改动**（PM 视角）：

- `skills/codebase-audit/SKILL.md` 加 **step 3.5 产品模块清单 + modulespec 主规格骨架**（PM 选择性触发）：现状档确认后问 PM「老项目 IA 已稳定，要不要现在建 modulespec 骨架？[Y/N]」。选 [Y] → AI 扫代码抽候选模块清单（子目录 / 路由 / 菜单 / PROJECT.md 业务模块段）→ PM 确认（必须）→ 按 `module.md.tmpl` 生成每个模块的 `docs/modules/<m>.md`（AI 填能扫到的部分：§摘要 / §一定位含**稳定结构指针 sub-bullet** / §三页面；§二功能清单 / §四 / §五保持空让后续 req sediment 演化）→ 刷 INDEX.md → PM 审 diff。选 [N] → 跳过，靠 close-req §1.5 step 2.5 兜底
- `skills/codebase-audit/SKILL.md` 「Rules」/「边界」段更新：默认仍只读扫码，**例外**允许 step 3.5 选 [Y] 时产 modulespec 骨架文件；明确「AI 不替 PM 决定模块边界」硬约束
- **greenfield 路径不动**：`/pmai-init-project` 保持现状（IA 未定，过早建会写一堆 placeholder），靠 close-req §1.5 step 2.5 按需生长

**影响**：

- 新 brownfield 接入项目：codebase-audit 多一个可选步骤；选 [Y] 后 close-req §1.5 step 2.5 反查在常见情况会零候选（真正退化成兜底）
- **已接入的老项目（如消费仓 ExampleConsumerApp）retroactive 补跑**：在主仓重跑一次新版 `/pmai-codebase-audit`（现状档可以跳过 / 简化，重点跑 step 3.5），把 modulespec 骨架补齐 —— PM 自行选择时机执行

### 2026-05-27 — feat(pmai-sync-prds): 一键补建老仓历史 closed req 的 docs/prds/ symlink

**触发**：上一条 `docs/prds/` 收口落地后，close-req / cancel-req 之后的新 req 会自动建 symlink，但**老仓在该改动之前关掉的 req 不会自动补**；PM 不想手动 `ln -sfn` 一行行敲。

**改动**：

- 新增 `bin/pmai-sync-prds`：在消费仓根 cwd 跑；扫 `requirements/closed/*/.req-meta.json`，按 status (`closed` / `cancelled`) 分流，调 `scripts/_lib/symlink-prd.sh` 的 `create_prd_symlink` 复用同套 helper（不重复实现）。无 prd.md / status 非 closed-or-cancelled 自动跳过。
- `bin/pmai` dispatcher subcommand 列表追加 `sync-prds`，支持 `--dry-run` 先看会做什么再实际跑。
- helper 路径解析按 `<cwd>/.claude/scripts/_lib/`（消费仓 install 后 default 路径）→ `<cwd>/scripts/_lib/`（本仓 dev）→ `$PMAI_HOME/scripts/_lib/` 三档兜底，default / --local / dev 三种安装形态都能直接用。
- `tests/test-symlink-prd.sh` 加 4 个 sync-prds e2e：无 closed/ silent exit / closed+cancelled+跳过类混合 / dry-run 不动文件 / 重跑幂等，全套 14/14 过。

**使用**：

```bash
cd <消费仓根>
pmai sync-prds --dry-run    # 先看会建哪些
pmai sync-prds              # 实际建
git add docs/prds && git commit -m "chore: backfill docs/prds/ symlinks"
```

### 2026-05-27 — feat(close-req+cancel-req+prd-writing): docs/prds/ 统一收口 req 关闭后 PRD 散落各处的查找痛点

**触发**：PM 反馈 —— req 关闭后 `prd.md` 散在 `requirements/closed/<req>/prd.md` 各目录里，要查"我做过哪些产品需求"必须挨个翻 closed 目录；想要一个统一入口。

**改动**（PM 视角）：

- 新增 `scripts/_lib/symlink-prd.sh` —— 提供 `create_prd_symlink <repo-root> <req-basename> <kind>` helper，被 close-req / cancel-req 共享；kind 取 `closed` / `cancelled` 决定落点；若 closed/<req>/prd.md 不存在 silent skip（兼容 stage 1/2 就 cancel 的 req 没写过 PRD）
- `scripts/close-req.sh` step 1b.5：merge 前在 req 分支建 `docs/prds/<req-name>.md` → `../../requirements/closed/<req-name>/prd.md`，和 archive 一起进同一 commit；merge 冲突回滚段同步清理空的 `docs/prds/`
- `scripts/cancel-req.sh` step 3：在 main 上 commit cancelled 占位前建 `docs/prds/废弃/<req-name>.md` → `../../../requirements/closed/<req-name>/prd.md`，一并进 cancel commit
- `skills/prd-writing/SKILL.md` standalone 入口 B「独立 PRD」分支加 step 7 收口：写入 `docs/独立PRD/<slug>.md` 默认路径时建 `docs/prds/独立/<slug>.md` symlink；PM 指定其他自定义路径不动
- 文档同步：`skills/build-close-req/SKILL.md` Phase 2 步骤 3 + `skills/cancel-req/SKILL.md` 步骤 2 脚本动作列表追加 symlink 行为一行

**最终结构**：

```
docs/prds/
├── req-001-用户登录.md  → ../../requirements/closed/req-001-用户登录/prd.md  (close-req)
├── req-002-付款.md      → ../../requirements/closed/req-002-付款/prd.md
├── 废弃/
│   └── req-003-xxx.md   → ../../../requirements/closed/req-003-xxx/prd.md   (cancel-req)
└── 独立/
    └── <slug>.md        → ../../独立PRD/<slug>.md                            (prd-writing standalone)
```

**影响**：消费仓下次 close-req / cancel-req 自动生效；symlink 进 git 追踪，clone 出来即可用；老仓不会自动补建历史 req 的 symlink（PM 想补：手跑 `ln -sfn` 或后续加 `pmai sync-prds` 命令）。

### 2026-05-27 — fix(close-req): §1.5 加稳定结构反查，堵 task 偏差表只能 diff「已有文档 vs 代码」的盲区

**触发**：消费仓 ExampleConsumerApp req-008 close 后 PM 反查发现菜单 IA（主运营 / 平台运营 / 租户三个 app 的 navigation 数据结构 + 菜单组织规则）只活在代码里 + `docs/DESIGN.md` §9.5，**没沉淀进任何 `docs/modules/<m>.md`**。三个 task 偏差表全部填「无」机器合规，但实质漏了 —— 因为偏差表是「已有文档 vs 代码」diff 算法，菜单 IA 在 modulespec 里从来没建过对应规格文件，「不一致」无从谈起 → §1.5 silent skip。

**根因**：close-req §1.5 输入源（task 偏差表 + adjustment 事件）只能检测「diff 类」偏差，检测不到「本 req 新建/改了稳定结构、但 `docs/modules/` 从来没建过对应规格文件」这种**结构性缺失**。

**改动**（PM 视角）：

- `skills/build-close-req/SKILL.md` §1.5 流程加 **step 2.5 稳定结构反查**：在 task 偏差表分组之后、PM 决议之前，AI 看本 req 全部代码侧 diff（`git diff $(git merge-base main HEAD) HEAD`），按正面线索（路径含 `routes`/`navigation`/`menu`/`schema`/`config` 等 + 内容是声明性数据 + 影响产品 IA）/ 负面排除（业务页面 / refactor / 测试 / bug fix）自答「本 req 是否新建/改了稳定结构但 `docs/modules/` 无对应规格文件」。输出候选「孤儿稳定结构」清单（含文件 / 类型 / 建议 modulespec 路径 / **AI 自审反证一行防过度推荐**），PM 三选一决议：**建** → 走 rewrite / **不建（追认代码即文档）** → close-report.md `## 文档变更` 段留追认记录 / **推下个 req** → close-report.md `## 遗留问题` 加点名
- §1.5 边界段 silent skip 条件加一项：**反查无候选孤儿（或所有候选 PM 选「不建 / 推下个 req」）**

**影响**：消费仓下次 close-req 流程 PM 视角多一个反查步骤（仅当 AI 反查产出候选时出 AskUserQuestion；零候选直接跳过）。本次未补 close-task 阶段反查（task 单位反查粒度太细且 task 没收完时反查不全面，留到本次反馈累积再说）。

### 2026-05-27 — fix(close-task+req-stage-gate): 关最后一个 task 时不再让 PM 多敲一次 /pmai-req-stage-gate

**触发**：PM 跑完 task-003（req-008 最后一个 task）后 `/pmai-build-close-task` 输出"下一步：在本（req）窗口运行 `/pmai-req-stage-gate` 推进至 Stage 7" → PM 敲 `/pmai-req-stage-gate` → 出关 req 确认门。PM 反问"closetask 之后都知道下一步是 stage7 了，为什么不直接和我确认是否要关闭 req"。

**根因**：`req-stage-gate/SKILL.md` 自己定的规则禁止"PM 请再跑一次 /pmai-req-stage-gate"这种 handoff 文案（v3.5 老行为，规则上线后视为违例），但 `close-task/SKILL.md` PENDING==0 分支跨 skill 边界把它伪装合规。close-task PENDING==0 时**已经 100% 确定**唯一下一步就是 6→7 关 req 确认门，没有任何分支模糊。

**改动**（PM 视角）：

- `skills/build-close-task/SKILL.md` 步骤 P2.4 PENDING==0 分支：不再打"请敲 /pmai-req-stage-gate"提示，改成 in-place 直接出 Stage 6→7 关 req 确认门；PM 答「确认 / 关」→ AI 跑 `req-transition.py --to 7` 推进 → 直接调用 `/pmai-build-close-req`
- `skills/req-stage-gate/SKILL.md` Stage 6→7 段头加注释 —— 标注本入口为兜底续走路径（PM 在 close-task 关 req 门不答关窗口后回来重敲的入口）；关 req 确认门模板单一真相源在 req-stage-gate，close-task 只复述

**PM 触摸 chat 次数**：4 → 3（task-submit 答 + close-task 不动 + 答关 req）。

**兜底场景仍走得通**：

| 场景 | 行为 |
|---|---|
| 不是最后一个 task | 现行分支不变，close-task 打印"下一步：task-XXX，跑 /pmai-task-spec → /pmai-task-confirm" |
| PM 在关 req 门不答关窗口几天回来 | 重敲 `/pmai-req-stage-gate`，req-stage-gate Stage 6→7 入口重新拉起同一个关 req 门 |
| PM 答"我还要加新 task" | close-task 转 `/pmai-task-spec` 起新 task，**不**推 Stage 7 |

**影响**：业务仓同步框架后 PM 在关最后一个 task 时少敲一次命令；模板单一真相源在 req-stage-gate，两边不会偏移。

### 2026-05-27 — refactor(同步资产): 清理生成器内部编号 / 归档死链 / commit hash 短引用 + hook 防回归

**触发**：PM 看到 `close-task/SKILL.md` 步骤 1 标题「文档偏差检查（D13 不调 doc-update）」追问"这里的 D13 是啥" —— 反向暴露**所有**同步到消费仓的资产（`scripts/` / `skills/` / `templates/` / `agents/`）里都积累了同类生成器内部知识债，消费仓 PM 看到完全不懂。

**清理范围**（58 文件）：

- **生成器内部设计任务编号**：`D13` / `D-iii v2` / `D-i v4` / `D-iv M1` / `D9-4` / `R3-C1` 等
- **管线小批次编号**：`delta-N` / `vp-N` / `polish-N`
- **归档路径死链**：`docs/归档/完成/...` / `docs/设计/...`（消费仓不存在这些目录）
- **短 commit hash 引用**：`commit 6382baf 同类 bug` / `(commit 07a3a09)` 等（消费仓 git log 不同）
- **开发日期戳**：「2026-05-16」/「2026-05-08」等内部时间线

**改造原则**：

- 删除内部编号但**保留 WHY 信息**（语义说明）—— 例：`"D13 final, 不调 doc-update"` → `"不调 doc-update（推迟到 close-req 末聚合，省 N 次启动成本）"`
- **保留**：`INVARIANTS.md` 的 `I-AD1` / `I-CT7` / `I-RT9` 等稳定 anchor（消费仓也分发 INVARIANTS.md）；同 SKILL 内部 `§N.M` 章节引用；业务编号 `task-NNN` / `req-NNN`

**hook 防回归**：新增 `hooks/check-sync-asset-jargon.cjs`（`.claude/settings.json` PreToolUse 注册）—— git commit 时扫 staged 改动 `+` 行，命中上述 pattern 拦下 commit，输出具体命中行 + 修法指引。逃生舱：commit message 加 `[skip-jargon-check]`。

**memory 沉淀**：`feedback_sync_asset_no_internal_ids.md`（同型规则的资产层延伸，与已有 `feedback_pm_chat_no_engineering_jargon` 互补：后者管运行时 chat 输出，前者管 SKILL.md / scripts 注释源头）。

**测试**：基线 525/2 —— 失败的 2 个（`test-init-project.sh T1/T2`）是 init-project.sh 重构为 symlink 模式后的 pre-existing stale test，跟本次清理无关。

---

### 2026-05-26 — chore(task-spec): 砍 task 确认门里教 PM 怎么读的元说明

task-spec 步骤 10 确认门输出里有一句「你确认的是 task 的 scope / 验收 / 反馈承接（PM 确认区），不是逐条背书实现细节。」—— req-008 task-003 确认时 PM 反馈"多余"。砍掉。

属于本批 PM-facing 输出清理的延伸（不属 banner-rules §2.5 的工程黑话 / 内部原理解释 E 类，是另一类：教 PM 怎么读 / 元说明）。目前只发现这一处，没必要立独立规则；未来再犯同类再考虑沉淀。

---

### 2026-05-26 — fix(pm-view + 4 skill): PM-facing 输出禁工程黑话与"AI 为啥这样安排"内部原理解释

**触发**：消费仓 task-002 跑完 task-execute 步骤 12「PM 通过 → 转已完成」后，AI 输出末尾给 PM 看一段「理由：Phase 1 必须在 task 窗口跑——agent 要直接读 task 改动的原型代码并把 task md 改动 commit 到 task 分支；跨 worktree 改会污染 req 分支历史。Phase 2 才切 req 窗口（删 task worktree 不能"删自己脚下"）。」 PM first-principle 质问"为啥要说理由"—— PM 信赖 AI 编排，不需要 AI 自证流程合理 / 不需要懂 worktree 切换的内部机制。这段不是 AI 临场加的，是 SKILL.md 第 557 行**明文写在 skill 里**的设计。

**全仓扫描结果**：同根因 5 处 PM-facing 输出塞内部原理 / 工程术语 —— `task-execute/SKILL.md:547-557`（PM 通过分支输出块 + 理由段）/ `task-submit/SKILL.md:195-203`（同 wording 备份入口）/ `task-execute/SKILL.md:250`（已完成状态错误退出提示）/ `close-task/SKILL.md:460-486`（Phase 1 收尾输出块 + DESIGN.md 沉淀追加提示）。共同模式：`Phase 1` / `Phase 2` / `finalize marker` / `auto-chain` / `merge → req` / `commit 到 task 分支` / `删 task worktree+branch` 等内部状态词与工程术语直接吐给 PM。

**根因**：banner-rules.md §2 只规定 Next Up 块的「格式 + 例子 + 何时打 + 渲染约束」，**没规定"内容禁忌"** —— SKILL 作者写输出块时无硬约束，逐字翻译内部实现给 PM 看就过了。需要在规则源补一条「PM-facing 输出禁工程黑话与内部原理解释」覆盖所有 SKILL 退出 / 状态转换 / 错误提示，否则只清现有 5 处下一个 SKILL 还会再犯。

**改动**：

- `skills/_shared/pm-view/banner-rules.md` 新增 §2.5「内容禁忌（PM-facing 输出禁工程黑话与内部原理）」：明文列 3 类禁项（内部状态词 / 内部实现术语 / "AI 为啥这样安排"原理解释）+ 允许保留清单（`task 窗口` / `req 窗口` / 命令名 / cwd 切换 —— PM 操作必需信息）+ 改写公式（工程版 → PM 版对照）+ 反例（PM 决策 picker 里的「AI 倾向 X，理由：<一行>」不受本规则约束，判定标准 = "帮 PM 做选择" vs "解释 AI 已做的选择"）。
- `skills/task-execute/SKILL.md` 步骤 12 PM 通过输出块：删 line 557「理由：Phase 1 必须在 task 窗口跑...」段；line 555 改 PM 视角动作描述「本次 close 收尾在当前窗口做完（文档对齐 + 视觉规范沉淀），完成后会提示你切到 req 窗口再跑一次 /pmai-build-close-task 完成清理。」+ 加引用 banner-rules §2.5。
- `skills/task-execute/SKILL.md` 步骤 §0「已完成」状态错误退出提示：删「启动 Phase 1（对齐/偏差/commit/写 marker），完成后会引导切到 req 窗口跑 Phase 2」，改「先在当前窗口做文档对齐和沉淀，再切 req 窗口完成清理」。
- `skills/task-submit/SKILL.md` 步骤 4 PM 通过输出块：同 task-execute 改写（task-submit 是步骤 11 的备份入口，完全相同 wording）。
- `skills/build-close-task/SKILL.md` 步骤 2.3 Phase 1 收尾输出块：「✅ task-NNN Phase 1 完成」改「✅ task-NNN 本窗口收尾完成」；「promote 到 docs/DESIGN.md（未 commit）」改「写入 docs/DESIGN.md（未 commit）」；「AI 会自动走 Phase 2 完成 merge + 删 task worktree/branch + auto-chain」改「切到 req 窗口跑 /pmai-build-close-task 后 AI 自动完成本 task 的归档，并自动开下一个 task（如果还有）」；DESIGN.md 沉淀追加提示「Phase 2 完成后，请在 req 窗口审 git diff」改「切到 req 窗口跑完 /pmai-build-close-task 后，请审 git diff」+ 「未 commit 的沉淀改动」改「未提交的沉淀改动」。

**保留不动**：
- `_shared/PM-VIEW-RULES.md:257`「决策的共同理由」、`req-stage-gate`/`task-plan` 多处「AI 倾向 A，理由：<一行>」—— PM 决策 picker 里 AI 列倾向理由给 PM 判断，是 PM-facing **必要素材**（不解释 AI 已做的选择），banner-rules §2.5 反例段已明文豁免。
- `task-execute:105` `cd` 沙盒原理、`task-plan:156` PRD 主线规范产物判定、`close-task:198` commit 到 task 分支理由、`input-flow.md:238` 原型 page.tsx 局部读判定等 —— 这些「理由：」在 SKILL.md prose 里给 SKILL 读者看，PM 看不到。

**关联反模式**：[[feedback-pm-chat-no-engineering-jargon]] 词典 ABCD 四类砍 —— 本条补齐"E 类：AI 流程编排原理解释"。

---

### 2026-05-26 — fix(task-verify + task-execute): verify pass 自说自话宣告 DONE，task 既没 commit 也没呈交

**触发**：消费仓 task-002-ops-menu-reorg 跑 /pmai-task-execute 到步骤 7.5 触发 task-verify，5/5 流程 pass 后 AI 在 verify 输出末尾**自己加了一段** `STATUS: DONE / REASON: ... / ATTEMPTED: ... / RECOMMENDATION: 回 task-execute 步骤 8 起继续走（写自审 placeholder → commit → 呈交 PM 验收）` —— 然后**停下来等下一轮**。结果：task 没 commit、没走步骤 11 呈交、PM 没看到任何呈交块。AI 把 verify pass 误当 task 终态宣告，PM 体感是"自说自话，没有呈交"。

**根因**：
1. task-verify 步骤 7 只规定了"pass 时 stdout 输出哪一行" + `exit 0`，**没明文禁止**额外文本 —— AI 觉得"加点交接细节有好处"就插了 STATUS/REASON/ATTEMPTED/RECOMMENDATION 块。
2. task-execute 步骤 7.5 pass 分流只写了「→ 进步骤 10 commit」，**没强调"不停 / 不汇报 / 不写交接块"** —— AI 把这里读成"可以先汇报一下当前状态再继续"，于是停在 RECOMMENDATION 文本等下一轮。
3. 两处缺的是同一句硬约束："verify pass 不是 PM 节点，PM 唯一决策点是步骤 11 呈交块"。

**改动**：
- `skills/task-verify/SKILL.md` 步骤 7：加「输出禁止扩写」段，明文列举禁项（STATUS: / REASON: / ATTEMPTED: / RECOMMENDATION: 交接块、指挥 task-execute 下一步动作如「回步骤 8 继续走」）+ 解释根因（task-verify 是 task-execute 步骤 7.5 调起的子流程，越界给"下一步建议"会让 AI 误判 task 终态、停下来等下一轮）。
- `skills/task-execute/SKILL.md` 步骤 7.5 pass 分流：扩为「**不停 / 不汇报 / 不写交接块**，自动接步骤 10 → 步骤 11 **一气走完**」+ 点名常见跑偏文本（`STATUS: DONE` / `RECOMMENDATION: 回步骤 8 继续走`）让 AI 自识别。

**关联反模式**：自说自话宣告 task 完成 ⊂ 「skill 流程没走完就声称已完成」家族 —— [[feedback_skill_must_actually_invoke]] (假执行)、[[feedback_close_default_flow]] (验收后默认走完)。本次是"验收前自说自话宣告完成"，补齐前置侧。

---

### 2026-05-26 — fix(task-execute): drift 脚本路径错位 + 失败容忍误吞「脚本不存在」

**触发**：消费仓 ExampleConsumerApp 跑 /pmai-task-execute 时 AI 报「drift 脚本未安装，按失败容忍原则继续」—— 实际是 SKILL.md 调用路径漏写 `.claude/`，bash 找不到脚本，AI 把 `No such file or directory` 错误归类为「未安装」+ 走失败容忍静默跳过 drift 保护。drift 是 4.5f 防 task agent 合法本地改动被覆盖的关键机制，跳过等于裸奔。

**改动**：

- `skills/task-execute/SKILL.md:143/188`：drift / apply 脚本调用路径 `$MAIN_REPO_ROOT/scripts/` → `$MAIN_REPO_ROOT/.claude/scripts/`，对齐同文件 228/242 行 task-transition.py / state.py 的正确路径风格。漏写 `.claude/` 是 commit 3c7fa49（4.5f drift 引入）原始 bug，生成器仓自跑无意义所以一直没暴露，第一次到消费仓真跑就触发。
- `skills/task-execute/SKILL.md`「失败容忍」段重写：明确区分两类异常 ——「脚本跑起来报错」走失败容忍（best-effort 兼容旧 sync-req-docs 行为），「脚本文件不存在」**不属于**失败容忍范畴、硬失败退出并报「框架版本/同步状态问题」+ 完整绝对路径。AI 禁说「脚本未安装」措辞（脚本是框架自带文件，不是第三方依赖；「未安装」会误导 PM 去 npm/brew install）。
- `skills/task-execute/SKILL.md` 入口步骤 2.4 bash 块加 `[ ! -f "$DRIFT_SCRIPT" ]` sanity check 把规则物化到执行流程，不是只写 prose。

**全仓回归**：`grep -rn '$MAIN_REPO_ROOT/scripts/' skills/ scripts/ templates/ agents/` 确认仅 SKILL.md 这两处漏写，其他都对。

---

### 2026-05-26 — feat(pmai): 框架分发与全局安装 v1.1 落地 — bin/pmai-* CLI + VERSION 0.1.0 + GitHub remote

**目标**：框架从"PM cd 生成器仓"hack 切到"pmai 全局 install + 任意 cwd 跑 /pmai-*"。详 [`docs/设计/框架分发与全局安装.md`](docs/设计/框架分发与全局安装.md) v1.1。

**改动**：
- 新增 `bin/`（6 个脚本，全 chmod +x）：
  - `bin/pmai`：主 dispatcher，路由 install/upgrade/uninstall/status/doctor/update-check
  - `bin/pmai-install`：2 模式（default 全局 git clone → ~/.pmai/ + symlink ~/.claude/skills/pmai-* | --local <dir> 实体副本）
  - `bin/pmai-upgrade`：档 2 版本管理（默认 main / --stable tag / --to pin）
  - `bin/pmai-uninstall`：清理（含 --force / --local <dir> 分支）
  - `bin/pmai-status`：install 模式 + VERSION + main HEAD diff
  - `bin/pmai-doctor`：6 项完整性自检（兜底 silent failure critical gaps）
  - `bin/pmai-update-check`：ls-remote latest tag 比对
- 新增 `VERSION` 文件 = `0.1.0`（档 2 起步 baseline）
- 新增 GitHub remote `git@github.com:YYG501/PMAI_Workflow.git`（PM 2026-05-26 push 首次 321 commit）
- `scripts/init-project.sh` 改造：`FRAMEWORK_DIR` 解析顺序变 `PMAI_HOME → ~/.pmai → cd ..`
- `README.md` 加「安装」段 + 改"快速开始"为 `/pmai-init-project` + 改命令表
- `CLAUDE.md` 加「框架分发与全局安装」段
- `框架同步-SOP.md` 标 DEPRECATED（T3 `pmai sync` 完成后归档；PM 决议暂缓）
- `docs/INDEX.md` 更新设计文档条目为「v1.1 实施中」

**review 决议**（10 finding，详设计文档 §X）：
- F-ARCH-1 A：消费仓 settings.json 写绝对路径 ~/.pmai/hooks/...，hook 不进全局
- F-ARCH-2 A：19 skill 加 pmai- 前缀（实测 22 skill + 1 _shared = 23 entries）
- F-TEST-1 A：T0 POC 现场验证 hook 进程 cwd = 消费仓根（与 hook 脚本物理位置解耦）

**T1.6 round-trip 实测通过**：install / doctor 7/7 / status / upgrade（修了 set -u 中文括号 unbound）/ uninstall 全部跑过；Claude Code 热加载 pmai-* skill 验证。

**暂缓项**（PM 5/26 决议）：T3 `pmai sync <consumer>` / T5 example-consumer-app 实战迁移 — 等无 active req 时再做，避免冲击当前在飞 req。

**影响**：纯新增机制（bin/ + VERSION + remote），不破坏现有 scripts/skills/templates/agents 任何逻辑；现役消费仓继续走 `框架同步-SOP.md`（DEPRECATED 但 active）。

### 2026-05-26 — fix(task-plan / task-execute / task-plan.md.tmpl): 反模式 A 文档类误判防复发（PRD 明文规范产物绕开 doc-update 路径）

**触发**：消费仓 ExampleConsumerApp req-008 task-001 执行时 AI 在 task worktree 改 `docs/DESIGN.md` 并 commit 到 task 分支 —— 越界保护放行（task md 「执行范围」allowlist 显式列了 `docs/DESIGN.md`）。回溯：task-plan stage 5 拍 §4.1 反模式自检 A 时，AI 把"PRD §6.1 决策必有产出 = 建立菜单组织规范段"按"反模式 A 重构类"处理（合并入 task-001 业务 task），实际框架明文要求"文档/规格/契约类前置 = 不立 task，走 /pmai-doc-update 沉淀"。AI 误读路径：PRD §6.1 用"必有产出"强语气 + AI 把"内容必须存在"和"什么时候写 / 走哪条 worktree"混为一谈，于是把文档产物塞进首个相关业务 task。

**改动**：
- `skills/task-plan/SKILL.md` §2.2 反模式 A "文档/规格/契约类前置"那条加明示：**包括 PRD §6.1 / §六 明文要求的"主线规范产物"**（建立规范段 / 字段字典 / 权限矩阵等）；产物归宿是 `docs/*` 即默认文档类，不合并进业务 task、不把 `docs/*` 写进 task 「执行范围」allowlist
- `templates/task-plan.md.tmpl` §4.1 反模式自检表头加分流规则段 + 反模式 A 行「命中处理」改为强制分类填写（"重构类 → 合并入 task-N" vs "文档类 → task-N close 后走 /pmai-doc-update 沉淀到 docs/X.md"），AI 拆完无法笼统填"已处理"蒙混
- `skills/task-execute/SKILL.md` 步骤 3 入口加 callout "task 边界硬规则"：明示 task worktree 内任何 `docs/*` 改动默认不属于 task 边界 + 视觉规范 / PM 反馈走 close-task §1.5 / PRD 主线规范产物走 `/pmai-doc-update`；发现 task md 执行范围含 `docs/*` 时 AI 主动提示 PM "疑似 task-plan §4.1 反模式 A 文档类误判，建议回 task-plan 调整"，由 PM 拍

**影响**：纯文档级提示加固（SKILL prose + template 字段），不改任何 script / hook / test，无回归风险。下次 task-plan 拍 §4.1 时 AI 看到 PRD 明文"建立 X 规范段"不会再机械合并进业务 task；万一仍误判，task-execute 进步骤 3 时会主动给 PM 提示要求回 task-plan 调整（软兜底）。**硬边界 hook**（task 分支不能 commit `docs/*`）作为 P1 改动留待后续，本次未做。



**触发**：消费仓 ExampleConsumerApp req-008 PM 跑完 `/pmai-task-spec task-001` 后被两件事卡住：
- (a) AI 输出"下一步运行 /pmai-task-confirm <task 文件路径>" 让 PM 复制粘贴 —— 多一道仪式；task-confirm 自身根本不设确认门（delta-3 §2.3 已固化），完全是机械流程
- (b) PM 临时问"几个 task 可以并行吗"，AI 才说"技术上完全可以并行，我默认写串行是 PM 体验考虑" —— 即并行 / 串行是 AI 自决，没经 PM 拍板。违反 speed mode 同批刚立的"结构决策必须 PM 拍板"原则（task-plan §二 执行模式是典型 task 级结构决策）

**改动**：
- `skills/task-spec/SKILL.md` 步骤 11 改名"落盘 + 续跑 /pmai-task-confirm"：commit 成功后 AI 不再输出"下一步运行 /pmai-task-confirm <path>"让 PM 复制；改为 chat 出一行轻量过场（"准备 task 执行环境..."）然后直接续跑 task-confirm workflow（同一 chat 内 Read task-confirm SKILL.md 按步骤执行）。失败兜底：commit 失败 / task-confirm 内部报错 → 把错误原文给 PM，**不**继续续跑；PM 修复后可手动调 `/pmai-task-confirm <path>`（旧路径作 escape hatch）
- `skills/task-confirm/SKILL.md` When To Use 段加"被 task-spec 步骤 11 续跑触发"分支，明确续跑路径行为与 PM 手动调一致（task-confirm 自身不设确认门）
- `skills/task-plan/SKILL.md` 步骤 3 后插入新步骤 3.5「PM 拍板执行模式（结构决策门）」：写完文件后主动 prompt PM 拍串行 / 并行 / 混合 + AI 给倾向 + 理由（同文件冲突 / 互相参照规范段 / task 数 / PM 走查负担）；PM 答完修订 §二 + append decision 事件（`decided_by=pm-explicit` + `source=task-plan@3.5`）
- `templates/task-plan.md.tmpl` §二「执行顺序与并行性」加 `**执行模式（PM 拍板）**：<串行 / 并行 / 混合>` 显式标记行 + 填写注释扩展（说明执行模式是 task 级结构决策、AI 不自决、走 task-plan skill 步骤 3.5 拍板）
- `tests/test-speed-mode.sh` 新增 T14-T17 4 case（task-spec 续跑文案 / task-confirm When To Use 续跑分支 / task-plan 步骤 3.5 关键词 / task-plan.md.tmpl §二 执行模式标记）

**影响**：PM 视角再削两道仪式 —— (a) `/pmai-task-spec` 定稿后**不再要 PM 手动贴 `/pmai-task-confirm <path>`**，直接看到 task worktree 路径 + Next Up 新窗口启动指令；(b) **执行模式（串行 / 并行 / 混合）从 AI 默认改 PM 显式拍板**，AI 给倾向 + 理由，PM 拍完写回 §二 + decision 事件 audit。续跑模式不引入新 escape hatch（commit 失败 / task-confirm 报错走老的手动调路径）。测试基线 512 → 516（+4 case 全过）。

**老 SKILL 流程的等价转换**：旧 `task-spec 步骤 11 输出 /pmai-task-confirm <path>` + PM 手动敲 = 新 `task-spec 步骤 11 续跑 + AI 自动跑 task-confirm`，对 PM 行为只是"少敲一次命令"，task-confirm 内部所有 worktree fork / executor 切换 / 依赖 gate 完全不变。

### 2026-05-26 — feat(req-stage-gate / templates / status-view): speed mode — PRD 拍板后 stage 4/5 自动推 + 结构决策门 + stage 6 入口总览

**触发**：消费仓 ExampleConsumerApp req-008 跑下来 PM 反馈"PRD 确定后，stage 4/5 应该一气推进"。查 req-008 实证：stage 3→4 间隔 0.1 秒、4→5 间隔 1.5 分钟、5→6 间隔 9 分钟 —— 流程时间总共 10 分钟，但 PM 还得回 4-5 次低价值确认门（"DESIGN 不动"、"impl-design 写完，过"、"task-plan 拆完，过"）。同时 implementation-design.md 7 个 HOW 决策里有 3 个（HOW-01 架构选型 / HOW-04 校验机制 / HOW-05 文档归位）AI 在写文件时悄悄自决，PM "看了，过"等于追认 —— 违反 memory `feedback_structure_decisions_need_pm`「结构决策必须 PM 拍板」。PM 否决 gsd 式 8 开关方案，选「1 个默认 mode + 严格清单」方向。

**改动**：
- `templates/implementation-design.md.tmpl` 段 1 HOW 表加「决策类型」列（结构 / 机械）+ 填写规则注释（备选≥2 个有效 → 结构；"—"/「已硬约束」→ 机械；拿不准默认结构）；段 1.5 SIMP 全表标注"视作结构决策"
- `templates/task-plan.md.tmpl` §一 task 表加「决策类型」列 + 填写规则（合并 / 拆开 / 重排 order / 反模式 A 命中 → 结构）
- `skills/req-stage-gate/SKILL.md` 顶部加 `## Speed Mode（默认行为）` 段（TL;DR + 自动推条件表 + 命中结构决策时 prompt 格式 + stage 6 入口总览 + 硬规则边界清单）；Stage 4 步骤 4C 加 speed 自动续条件（gap-check 无新缺 + DESIGN 不改 → 跳完整确认门）；Stage 4→5 步骤 5a-gate 改 speed 行为（扫段 1 HOW 表 + 段 1.5 SIMP 表，逐行 prompt 结构决策；无结构决策直进 5b）；Stage 5→6 全段重写（扫 task 表逐行 prompt 结构 task → 调 `status-view.py --stage6-entry` 出总览 → PM 三选 ✓ / ↺ / ✗）
- `scripts/_lib/stage6_summary.py` 新建（~280 行）—— stage 6 入口总览模块；解析 implementation-design.md 段 1 / 段 1.5 + task-plan.md §一 + §二 启发式抓 execution mode；渲染【AI 自决 N 件】+【PM 拍过 M 件结构决策】+【task 拆分】+【产物路径】+【可选 review】+ PM 三选
- `scripts/status-view.py` 加 `--stage6-entry <REQ_DIR>` argparse + main 分支；从 req_dir 反推 worktree repo_root（不用调用者 cwd，否则跨仓 DESIGN.md 路径错位）
- `tests/test-speed-mode.sh` 新增 13 case（argparse / 模块函数 / 模板列 / SKILL 段 / fixture 全机械 / 全结构 / 老 req 兼容 / SIMP 归位 / 结构 task / CLI exit / Stage 4 文案 / Stage 5→6 调用）
- `tests/test-implementation-design.sh` 更新 `test_stage_gate_wiring`：旧"implementation-design 待确认"全文门字符串校验改为 speed mode 关键文案（"implementation-design PM 决策门" / "命中结构决策"二选一）

**影响**：PM 视角操作次数从 ~7 次降到 ~6 次（数量差不多），但**质量大变** —— 0 次低价值"看了，过"门、N 次结构决策被前置到决策当下问、stage 6 入口给一次性总览（自决项 + PM 拍过项 + task 拆分 + 产物路径，PM 一眼判断是否进 task 执行）。**老 req 兼容**：已存在的 implementation-design.md / task-plan.md 无「决策类型」列 → 现场推断默认按结构（保守 / 每行都问，宁可多停一次）；不强制迁移老文件。**硬规则保留**：Stage 1-3 流程不变、未决问题闸门不变、PRD 决策门不变、Stage 6 task 执行不变、Stage 7 close 不变。测试基线 460 → 512/0（+52；本次新加 13 case 全过）。

### 2026-05-26 — feat(req-events / prd-writing / req-stage-gate): decision 事件加 decided_by 区分 PM 拍 / AI 推断

**触发**：req-008 stage 4 入口 AI 文案把"规范放进 DESIGN.md"说成"PM 之前拍过"。查 `req-events.jsonl` 发现 6 条决策全是 stage 3 AI 写 PRD 时 166 毫秒内批量 append 的，`source=prd-writing@3`，无法区分「PM 在确认门主动开口拍的」 vs「AI 单方面推断的」。下游（stage 4 文案 / status-view / 后续 stage）读 decision 事件时无法识别，把 AI 自拍决策表述为"PM 决策"，违反 memory `feedback_pm_decision_is_binding_contract` 的"PM 决策 = binding contract"前提（"分得清谁拍的"）。

**改动**：
- `scripts/req-events.py`：decision 事件加 `--decided-by` **必填**（`pm-explicit` | `ai-inferred`），缺 / 非法值 exit 1；`cmd_list` 渲染按 `decided_by` 分三组（`[PM 拍]` / `[AI 推断]` / `[未分类 legacy]`，legacy 段兜底字段引入前的旧事件）
- `skills/prd-writing/SKILL.md` 步骤 3.7：调用模板加 `--decided-by`；新增「判定标准」段（PM 在 stage 1/2/3 events 里有原话 → `pm-explicit`；否则 / 拿不准 → `ai-inferred`，明确"AI 推得很清楚 / 看起来显然只能这么选"**不构成** `pm-explicit` 理由）
- `skills/req-stage-gate/SKILL.md` stage 3 定稿确认门：🧭 决策段强制分两子段（`[PM 拍]` 只列标题+选定；`[AI 推断]` 列标题+选定+备选+理由）；AI 推断段默认通过，PM 反对的单挑说条目号；模板要点同步标注「PM 视图禁出现 `decided_by` / `pm-explicit` / `ai-inferred` 字段名」
- `tests/test-req-events.sh`：新增 4 case（缺 --decided-by 报错 / 非法值 argparse 拒绝 / list 按 decided_by 分两组渲染 + 计数 / 旧 decision 事件归 legacy 段）

**影响**：decision 事件流恢复"分得清 PM 真拍 vs AI 自拍"，下游 stage 文案 / status-view 不会再把 AI 自拍说成 PM 决策；stage 3 定稿确认门多一项"AI 推断段单挑反对"语义（默认全过，PM 反对时 AI 临场决定修订粒度）。req-008 已有的 6 条决策事件保留作 `legacy` 段（append-only 不修复历史；按新判定标准重新分类要 PM 单独操作，本次不做）。测试基线 +4 case。

### 2026-05-26 — fix(prd-writing-lint): 加类 3 表格结构检查 + 消除规则源冲突

**触发**：req-008 PRD `§6.1-6.5` 五个表格全部用 `<br/>` 把多条编号塞**单元格**，违反 `PM-VIEW-RULES.md §5.1`「续行 rowspan + 每条编号独立一行」硬规则。PM 走查发现。**3 层根因叠加**：
- (a) **规则源冲突**：`PM-VIEW-RULES.md §5.1` 权威规定续行 rowspan；`writing-rules.md §3.12.8` 正例却用 `<br>` 塞单格 —— 两套规则互相矛盾，AI 看到必挑容易的
- (b) **lint 漏检**：`scripts/check-prd-hierarchy.py` 类 1 / 类 2 都没覆盖**表格结构**，`<br/>` 塞单格通过 lint 直接进 stage 3 定稿门
- (c) **AI 倾向**：表行少 = 输出少，单格 `<br>` 是天然的"省事写法"

**改动**：
- `skills/_shared/pm-view/writing-rules.md §3.12.8` 正例改写：保留"流程式分条"核心论点，但例子从 `<br>` 单格换成续行 rowspan 4 列表格；显式标注「编号条目放需求描述列时按 §5.1 续行 rowspan 渲染、禁 `<br/>`」消除规则源冲突
- `scripts/check-prd-hierarchy.py` 新增 **类 3 — §六 表格结构**：扫 §六 所有表格的「需求描述」列出现 `<br/>` / `<br>`（任意大小写）即 fail，附 cell preview + 编号项数 + 修正示例；退出码语义与类 1 / 2 一致
- `tests/test-prd-hierarchy-lint.sh` 新增 4 个 case（T1 类 1 UI 词 / T2 类 2 描述风格 / T3 类 3 `<br/>` 违规 / T4 类 3 续行 rowspan 正例）；接入 `tests/run-all.sh`

**实战验证**：拿 req-008 PRD 实跑 lint，类 3 正确抓到 **26 处违规**（§6.1 / 6.2 / 6.3 / 6.4 / 6.5 全覆盖）。消费仓 PRD 需按续行 rowspan 重渲（PM 单独操作）。

**publish-to-lark 合并验证**：发布到飞书时由 `scripts/publish-to-lark.py:merge_desc_group_with_content` 把续行 rowspan 多行 group 合并回单格（非锚点 cell 的 children 拷贝到锚点 cell + 清空原 cell + `merge_table_cells` API）—— 视觉等同有序列表换行。新增 `tests/test-publish-to-lark-rowspan-merge.py` 单测 `find_desc_group_ranges` 6 case 覆盖单 group / 多 group / 单行不合并 / 空 grid / 单列 / existing 冲突过滤，保证续行 rowspan → 飞书单格合并的语义。

**影响**：PRD lint 多一道结构防线（同 task-execute 步骤 2.0 / prd-writing 0.5 「机械强制 > LLM 自觉」哲学）；规则源单一真相源恢复到 `PM-VIEW-RULES.md §5.1`；续行 rowspan markdown → 飞书单格合并已被单测兜底。测试基线 +5 case（lint 4 + publish-to-lark 1）。

### 2026-05-26 — feat(askuser-rules / review-skill-guard): 固化 memory 反思（A1 PM 逐条决策 + A3 评审先扫现状）

**触发**：盘点生成器仓 22 条 memory + 消费仓（ExampleConsumerApp）5 条 memory，识别 4 个未固化到框架的反思项，最终决定做 P0 + P1 两项（A2/A4 留 backlog）：
- A1：消费仓 memory `pm-plain-language-one-decision-at-a-time.md` 记录 PM 多次驳回"术语密集 + 批量 AskUser"，但 `_shared/pm-view/askuser-rules.md` 不含「多决策必须拆开顺序问」硬规则 → 新消费仓 PM 必踩同样坑
- A3：生成器仓 memory `feedback_autoplan_preread_existing_skill.md` 记录 D13 前 5 轮 autoplan 评审无一发现仓库已有 `req-stage-gate` 等机制，但 `hooks/review-skill-guard.cjs` GUARD_TEXT 不含「评审前先扫项目现有机制」约束 → 下次跑 autoplan 仍会翻车

**改动**：
- `skills/_shared/pm-view/askuser-rules.md` §1 标题从「3 条硬规则」改「4 条硬规则」+ §1.3 后插入 §1.4「多决策必须拆开顺序问」（触发场景 / AI 行为 / 反例 / 正例 / Why / How to apply 全段）
- `hooks/review-skill-guard.cjs` GUARD_TEXT 在「FORCE stance」之后插入「Ground in 现状」段：评审 agent 必须先 grep `skills/`/`hooks/`/`scripts/`/`docs/` 找现有同主题机制，找到→优先复用、找不到→才新增；对调用方（autoplan / plan-eng-review）同样生效，派子 agent 前注入"先 grep 现状"指令

**影响**：
- 所有用 AskUserQuestion 的 skill（req-stage-gate / new-req / task-confirm / close-task 等）通过 §1 顶部引用自动继承 §1.4 约束；不需要逐 skill 改
- review-skill-guard hook 触发 review/audit 类 skill 时自动注入新增段（消费仓 hook 文件已同步生效；新 git pull 即生效）
- 不涉及代码逻辑改动，纯文档 / 注入文本调整；测试基线无变化

**未做（留 backlog）**：A2（推翻类 req 不引用同源文档作权威）+ A4（audit 挡 task 通用诊断顺序）—— 低频场景，固化成本/收益比不划算

### 2026-05-26 — fix(req-analysis / implementation-design / task-plan / task-spec): 项目级文档强制 echo 同款修法

**触发**：prd-writing 落 0.5 / 1.5 强制 echo 修复后审计同类 skill，发现 4 个 orchestrated skill 有同款漏读风险，且 task-plan 行 78 / task-spec 行 101 已经写了 prose 警告「AI 不得以'觉得不必要'为由跳过」—— **说明框架早就识别这个失效模式，但只用 prose 防御无效**。本次按 task-execute 步骤 2.0 / prd-writing 步骤 0.5 同款修法批量补齐。

**改动**（每个 skill 同款 Bash `cat` echo 模式，按各自 small-bounded-full-read 输入裁剪）：
- `skills/req-analysis/SKILL.md` 新增步骤 0.5（brief + PROJECT + modules/INDEX）+ 步骤 1 改名「消化已 echo 输入 + 识别涉及模块」+ 增量分支步骤 1.5（涉及模块 spec 强制 echo）
- `skills/implementation-design/SKILL.md` 新增步骤 0.5（prd 全文 + stage2源 + brief + PROJECT + DESIGN 组件 inventory）+ 步骤 1 改名 + 步骤 1.5 涉及模块 spec
- `skills/task-plan/SKILL.md` 新增步骤 0.5（brief + stage2源 + implementation-design + PROJECT + modules/INDEX）+ 步骤 1 改名「消化已 echo 输入 + 按既有强约束读 slice-read 项」；prd（§9.1.1 切片）+ prototypes（§9.3 >500 行禁）+ DESIGN（按需 grep）保持既有强约束读法，**不**全文 echo
- `skills/task-spec/SKILL.md` 新增步骤 2.5（task-plan + PROJECT + **PRODUCT-RULES delta-9 全文** + modules/INDEX）+ 步骤 3 改名；prd / impl-design / 模块 spec / PRODUCT-RULES 域限定段保持既有 §9.1.1 章节-grep，**不**全文 echo

**通用模式**（4 skill 共享，便于后续 audit / 维护）：
- 强制 echo 范围 = 全文 small-bounded 必读项（brief / stage2源 / PROJECT / PRODUCT-RULES 全局段 / modules/INDEX / 必读架构文档）
- 不 echo 范围 = 已有 §9.1.1 章节-grep 切片读约束的 / §9.3 prototype 强约束的 / 按需 grep 局部读的（避免大文件污染 context）
- LLM 在「消化已 echo + 识别涉及模块」步骤后填 `MODULE_SPECS` 数组，跑步骤 X.5 echo 涉及模块 spec（同 prd-writing 1.5）

**影响**：4 个 orchestrated skill 漏读概率从「依赖 LLM 自觉」降到「shell 跑了就在」；prose 警告（task-plan 行 78 / task-spec 行 101）保留但已退居二线（强制 echo 是主防线）。测试基线无回归（流程注入 Bash echo，机械可见）。

### 2026-05-26 — fix(prd-writing): 项目级文档强制 echo 防 LLM 自觉漏读 + DESIGN.md 移出输入清单

**触发**：PM 在 req-008 stage-3 实战中发现 AI 跳过项目级文档读取直接拆 §六，质疑「skill 写了『先读项目级文档』为什么没读」。根因：prd-writing stage-3「Required Inputs」是 prose 清单（依赖 LLM 自觉调 Read tool），与 task-execute 步骤 2.0 强制 `cat` echo 模式是同一类失效（task-001 反复迭代踩坑的根因「Read tool 触发与否取决于 LLM 自觉」）—— 同款问题、同款修法，prd-writing 没复用。

**改动**：
- `skills/prd-writing/SKILL.md` 新增步骤 0.5「项目级文档强制 echo」（stage-3 模式必跑；standalone 模式 PM 在线可省）：Bash `cat` 把 `brief.md` + stage 2 真相源 + `PROJECT.md` + `PRODUCT-RULES.md` + `modules/INDEX.md` 全文无条件压进 transcript，保证 working context 到位
- 步骤 1 标题从「读入 + 拆决策」→「拆决策 + 识别涉及模块」（基于步骤 0.5 已 echo 的内容），把"读"和"拆"解耦，LLM 不再能把"读"当暖场跳过
- 新增步骤 1.5「涉及模块 spec 强制 echo」：步骤 1 识别完本 req 涉及模块后，`cat` echo 每个模块的主功能规格文件（INDEX.md「当前文档路径」列）；不机械 echo 整个 modules/ 目录避免污染 context；单模块 spec 全文 echo 不截读
- DESIGN.md 从输入清单移出 —— 行 75 / 76 / 109 三处去掉：DESIGN.md 在 prd-writing 只作**反向边界提示**（"PRD 不写像素颜色 / 视觉规范归 DESIGN.md"），不作正向源材料；正常信息流是 PRD → DESIGN.md（功能定义 → 视觉规范），反向读 489 行全文进 context 浪费且违背流向。视觉规范的正向读由 implementation-design / task-execute 承担（task-execute 步骤 2.0 已强制 echo）
- 行 30 / 47 / 126 同步更新：stage-3 短路后流程串改为「步骤 0.5 → 步骤 1 → 步骤 1.5 → 步骤 2」；Workflow 起首说明加「stage-3 必跑 0.5 / 1.5；standalone 可省」

**影响**：stage-3 模式 PRD 写作前项目级文档 + 涉及模块 spec 必进 context（不再依赖 LLM 自觉）；DESIGN.md 不再为 prd-writing 浪费 489 行 context。无测试改动（流程注入 Bash echo，机械可见）。

### 2026-05-26 — fix(prd-writing): §六拆分预处理强制 PM 确认门 + 去工程黑话

**触发**：PM 在 req-008（导航结构重整）stage-3 实战中遇两个问题 ——（1）AI 按步骤 2.5「stage-3 模式下 AI 自判无歧义可直接进步骤 3」的旧规则跳过 PM 拍板，PM 失去对菜单 / 模块归类的结构裁判窗口（之前要等 PRD 全文写完才能改）；（2）展示给 PM 看的拆分预览塞满工程黑话——「§六 拆分预处理」「黑名单扫描：✓ 全部通过」「下沉到需求描述列」「动作组」「二级 / 三级」「步骤 2.5」全是 PM 看不懂的内部章节号 / 内部规则名 / 模型术语。

**改动**：
- `skills/prd-writing/SKILL.md` 第 33 行（入口 A 确认门字段）：从「只在 AI 判断有歧义时才询问 PM」改为「必有 PM 确认门，AI 不允许自判无歧义跳过；本门确认结构，stage-gate 定稿门确认成品」
- 第 126 行（Workflow 起首说明）：同步收敛为「两入口都强制 PM 确认门」
- 步骤 2.5 a/b/c/d 通用化（不再把"用户动作"当唯一组织维度）：
  - a「动词清单优先」→ 「选定组织维度」：先认定本 req 业务本质对应的一致维度（CRUD = 动作 / IA 重整 = 分组 / 配置 = 设置项 / 流程 = 步骤），所有二级 / 三级围绕同维度展开；维度判定优先级 stage 2 真相源明示 > 业务本质推断 > e 步骤请 PM 拍板
  - b 命名风格随维度变（动词 / 名词分组词 / 设置项名 / 步骤名），不再写死"只允许动词或动词派生名词"
  - c 黑名单保持（跨业务通用），重写示例补全 4 类维度版本（动作 / 分组 / 设置项 / 流程），加「菜单」例外说明（IA 业务核心词允许保留但仍不作为二级 / 三级命名本身）
  - d 下沉规则保持（跨业务通用）
- 步骤 2.5 e 整段重写：
  - PM 展示模板标题用「功能模块拆分」（替代旧标题「§六 拆分预处理」）
  - 去掉「§六」「拆分预处理」「reorg pass」「黑名单扫描」「下沉到需求描述列」「动作组」等工程章节号 + 内部规则名 + 模型术语
  - **「一级 / 二级 / 三级功能」保留**（PRD §六层级标准术语，PM 看 PRD 时本就是这套，chat 用同名反而一致）
  - 模板顶部加「AI 一句话说明组织维度 + 理由」段（用 PM 大白话 / req 业务本质对应的具体词，不照搬 a 表格"维度"二字；占位符 + 示例形式，不写死替换词）
  - 改用 PM 视图语言：「细节会写进对应三级功能的需求描述里」/「哪些要改 / 加 / 删 / 调整归类（含维度选取本身）」
  - 门规则从「stage-3 默认采用 / standalone 才问」改为「两入口都等 PM 拍板（OK / 改）」
  - 黑名单命中由 AI 自己重写后再展示**最终版**给 PM，违规原命名不贴给 PM（看了反而困惑）

**影响**：PM 拍板时机前移到拆分阶段；PM 看到的 chat 文案与 `_shared/pm-view/writing-rules.md` §3.12「禁工程黑话」对齐。无测试改动（流程文案调整）。

### 2026-05-26 — refactor(analysis-reviewer): 借鉴 Claude 官方 code-review 重构反馈框架

**触发**：PM 反馈实战 reviewer 输出（req-008-reorganize-menus）有三类问题 ——（1）二元 PASS/FAIL 一刀切，3 条 finding 全打 FAIL 但实际含 nit + 误报 + 真问题混杂；（2）跟 analysis 法定结构第 7 章「拟采取方案」打架（要求方案延后到 stage 3，但章节本就要给方案）；（3）输出工程黑话太多、信息量超出 PM 阅读体量。

**方法论参考**：[Claude 官方 code-review skill](`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/code-review/commands/code-review.md`) 的核心机制 —— 置信度 0-100 + 阈值过滤 + 显式 false-positive 清单 +「focus on large bugs, avoid nitpicks」硬约束。

**改动**：
- `agents/analysis-reviewer.md` 整体重写：
  - 引入置信度方法论：80-100 = 必改 / 60-79 = 建议改 / 40-59 = 锦上添花 / < 40 = 不报
  - 顶层加 8 条 false-positive 清单（§七拟采取方案有内容 / 文档存放路径 / 排版 / 倾向性分析视为缺陷 / 方案融合呈现 / typo / 主观印象 / 评 PM 决定本身），命中直接丢弃不打分
  - 4 角度只保留「找什么 + 真问题样例」，「不算问题」段合并到顶层 false-positive 清单
  - 输出格式精简：取消"角度通过/失败"占位、空段不出现、blocking ≤ 5 / 全部 ≤ 10
  - 加禁用词表：未决问题 section / stage 3 / 决策耦合 / 对齐粒度 等工程黑话改 PM 大白话
  - 砍 PASS / NEEDS_REVISION 英文字面输出，主线 skill 改靠 grep 「## 必改」段判定
- `skills/req-analysis/SKILL.md` 步骤 5 同步：
  - 加 5.0「判定走哪个分支（机械化，不靠语义猜）」段：靠 `## 必改` 段存在性判定
  - 5.1 通过分支文案补一句「报告里还有 N 条建议 / M 条锦上添花，都不阻塞下一步」
  - 5.2 文案从「⚠️ 评审反馈了改进建议」改「⚠️ 评审说有 N 条必改」
  - 退出契约 `review_outcome=PASS` 定义从「reviewer 返回 PASS」改「报告无必改条目」
  - Common Mistakes 里 PASS/NEEDS_REVISION 文案中文化
- `skills/req-stage-gate/SKILL.md`「闸门挂起等 PM」清单 + 「analysis 评审 NEEDS_REVISION」PM 视图提示中文化

**影响**：
- 反馈信号区分度变高 —— nit 不再凑出 FAIL，PM 真能跳过；置信度阈值机械化挡掉低质量 finding
- 输出长度上限明确（必改 ≤ 5 / 全部 ≤ 10）—— 治"PM 看不动"
- 禁用词清单覆盖实战出现的 8 类工程黑话 —— 治"读不懂"
- 接口契约（`review_outcome` enum）不变，业务仓续 req 无需迁移
- 测试无回归（agent + skill 文档级改动，无脚本逻辑）

### 2026-05-26 — refactor(term-detector): 二次迁移到 close-req + 临时/长期双词典分层

**触发**：承接上一条 `term-detector 调用点收敛到 prd-writing 一处`。PM 进一步反馈：业务实体真正稳定要等 task 都执行落地，PRD 阶段（stage 3）就 patch PROJECT.md 长期术语表偏早；并发现 implementation-design / task-spec 没有显式"读术语表"的必读项，业务术语没有传递机制。

**设计变化**（临时词典 vs 长期词典分层）：
| 层级 | 文件 | 谁写 | 谁读 |
|---|---|---|---|
| 本 req 临时词典 | `prd.md §三 名词解释` | `prd-writing` 写 PRD 时 AI 直接落地 | `implementation-design` / `task-spec` 必读 |
| 跨 req 长期词典 | `docs/PROJECT.md ## 业务术语表` | `close-req` 步骤 3.4 detector + PM 确认 | `implementation-design` / `task-spec` 必读（与 PRD §三 并集读）|

**改动**：
- `skills/prd-writing/SKILL.md` 步骤 3.6 砍掉 detector 调用，改成纯文本说明「PRD §三 = 本 req 临时词典；patch PROJECT.md 推迟到 close-req」；同步更新 stage 3 边界 / 收尾段
- `skills/build-close-req/SKILL.md` 新增步骤 3.4「业务词催补 hook」（推进 stage 7 之后、里程碑追加询问之前），detector 输入 = `prd.md` + 全部 `tasks/closed/*.md`
- `skills/implementation-design/SKILL.md` Required Inputs 新增两行：`prd.md §三`（临时词典）+ `docs/PROJECT.md ## 业务术语表`（长期词典）
- `skills/task-spec/SKILL.md` Required Inputs 同上新增两行
- `skills/_shared/term-detector/SKILL.md` description / 何时调用 / 禁止位置 全段重写，新增「临时词典 vs 长期词典」对照表段
- `skills/_shared/pm-view/input-flow.md` §9.4.2 routing 表「用词 / 术语」行拆成两行：本 req 临时 → PRD §三；跨 req 长期沉淀 → close-req detector
- `skills/req-stage-gate/SKILL.md` Stage 2→3 描述里残留的「跑 term-detector 补 PROJECT.md」字样 + 4B 注释里的「收敛到 prd-writing 3.6」清理一致

**影响**：
- detector 触发次数不变（1 次/req），但时机从 stage 3 推迟到 stage 7
- impl-design / task-spec 用业务术语有显式词典支撑（之前是隐式依赖 AI 读 PROJECT.md 整文消化）
- 测试无回归
- 业务仓影响：消费仓如果在「prd-writing 跑 detector」阶段已用过老流程，老 PROJECT.md 业务术语表里的内容不动；下一个 req 起按新流程跑

### 2026-05-26 — feat(docs-toplevel-guard): pre-commit hook 拦截 docs/ 顶层错位文件

**问题**：扁平化约定（见下面 fix(docs-archive-convention)）只是写在 CLAUDE.md 里靠 PM + AI 自觉。AI 写新文档时不一定真按约定归位，PM 也未必 review 路径 —— 长期还是会积累错位。

**改动**：
- 新增 `scripts/check-docs-toplevel.py`：检测 staged 新增 `docs/<basename>.md` 是否在白名单（静态：`PROJECT`/`DESIGN`/`PRODUCT-RULES`/`ROADMAP`/`prd`/`CONTEXT`；可扩展：`.docs-toplevel-allow` 一行一 basename）。错位 → exit 1 + 列文件 + 提示归位 3 路径
- `templates/git-hooks/pre-commit.tmpl` 增加调用 `check-docs-toplevel.py` 段；脚本缺失 fail-open（老消费仓还没 sync 时不阻塞）
- `templates/CLAUDE.md.tmpl` 归档约定段补「自动守卫」小节，说明 hook + `.docs-toplevel-allow` + 救火绕过 `--no-verify`
- 新增 `tests/test-docs-toplevel-guard.sh` 8 case

**消费仓影响**：
- 新项目 `/pmai-init-project` 自带 hook + 检测脚本 + CLAUDE.md 约定
- 老项目 sync 框架后 **要跑** `bash .claude/scripts/install-hooks.sh` 重装 hook 才能启用
- 暂时不想被拦：`git commit --no-verify`，或把 basename 加进 `.docs-toplevel-allow`

**测试基线**：482 → 490（+8）

### 2026-05-26 — fix(pm-chat): Stage 1→2 选择门 + office-hours 子状态 + PASS 闸门 文案去工程黑话

**问题**：PM 实测 `/pmai-req-stage-gate` Stage 1→2 入口文案「这版 brief 是否可定稿？然后用哪种方式跟这个需求讨论？」一句塞两问；选项描述「结构化批判 / 第一性原理 4 层 / reviewer / YC office-hours / 跳 reviewer」全是内部机制名。office-hours 三个子状态（探测失败 / 选稿 / 没现成稿）泄露「按 mtime 排 / gstack slug / 切回结构化批判分支 / snapshot 进 Stage 2 真相源」。req-analysis PASS 闸门还在用 v2 旧句式（破折号 + "OK 我..."），与 req-stage-gate L425 自己列的反面示例自相矛盾。

**改动**：
- `skills/req-stage-gate/SKILL.md`：
  - Stage 1→2 入口改 v3 单问句 + 「结构化挖透 / 开放探讨 / brief 还要改」三选项，每条带 PM 视角的"对你意味着什么"一句话；删冗余「需求讨论入口 / 一句话摘要」
  - office-hours 三子状态去黑话：「按 mtime 排」→「按更新时间倒序」、「源材料」→「讨论稿」、「gstack slug / office-hours 分支」泄露删除
  - resume / B 推进确认门：「snapshot 进真相源」→「接进当讨论稿」，统一 v3 定稿句式
  - dispatch 关键词双向兼容：新词「结构化挖透 / 开放探讨」+ 旧词「结构化批判 / office-hours」都接得住
- `skills/req-analysis/SKILL.md` PASS 闸门 v2 → v3 统一定稿句式
- `skills/_shared/pm-view/banner-rules.md` §3.0 示例引用同步新标签

**影响**：纯 PM 视图文案，无逻辑改动；dispatch 双向兼容确保 PM 用旧词也接得住；无新增测试。

### 2026-05-26 — fix(docs-archive-convention): 归档子目录扁平化（删 完成/ + 旧版/ 二分）

**问题**：上一版（`8a41de5`）把 `docs/归档/` 分成 `完成/` + `旧版/` 两个子目录。PM 反馈两个子目录**语义不在同一维度**：
- "完成" 是按生命周期（在飞 → 完结）
- "旧版" 是按版本继任（被取代）

混搭分类让 PM / AI 实际归档时第一反应是"这放哪个"，反而增加摩擦。且"完成"跟生成器仓 `docs/归档/完成/` 装"已落地的设计文档"语义冲突。

**改动**：
- `templates/CLAUDE.md.tmpl` 归档约定段：归位规则改成统一进 `docs/归档/`，文件名 / commit message 自己说明为啥归档
- `scripts/init-project.sh` 不再建 `完成/` + `旧版/` 两个子目录，只建一个 `docs/归档/.gitkeep` 扁平骨架
- `tests/test-docs-archive-convention.sh` T3/T5/T6 同步更新（含负向断言：子目录不该再被建）
- 文件名后缀策略：`-原始` / `-v1` 后缀加在文件名里标明历史版本（如 `登录页-原始功能清单.md`）

**消费仓影响**：尚未 sync 上一版 `8a41de5` 的项目（包括 ExampleConsumerApp）—— 本 fix 替代它，sync 后直接是扁平版。已 sync `8a41de5` 的项目（暂无）→ 手工删 `docs/归档/{完成,旧版}/` 子目录即可。

### 2026-05-26 — feat(docs-archive-convention): 消费仓 docs/ 归档约定（防顶层积累错位 / 重复 / 过期文件）

**问题**：PM 实测 example-consumer-app docs/ 顶层有：
- 错位：`product-principles.md`（部门 / 用户 / 角色决策）+ `user-stories-permission.md`（权限用户故事）—— 是模块级决策却放顶层
- 重复：`prd.md` 跟 `PROJECT.md` 内容重叠
- 过程档案：`PROTOTYPE_CLEANUP.md`（清理过程档案）放根目录
- 旧版本：`xxx 原始功能清单.md`（被 v2 取代）跟新版同处一目录

**根因**：framework 完全没约定消费仓 docs/ 怎么组织 —— 新建文档时 AI 随手放顶层，长期积累混乱。

**改动**：
- `templates/CLAUDE.md.tmpl` 加「## docs/ 归档约定」节：
  - 顶层 docs/ 正面清单（PROJECT / DESIGN / PRODUCT-RULES / ROADMAP / prd + 项目级业务概览 + modules/ + 归档/）
  - 顶层负面清单 + 归位规则表（模块决策 → `docs/modules/<模块>/`；过程档案 → `docs/归档/完成/`；被取代的旧文件 → `docs/归档/旧版/`）
  - 写新文档前 AI 自问 3 题（作用域 / 路径 / 命名冲突）
  - 命名规范（项目级全大写 / 模块文档 kebab-case / 顶层禁 v1 v2 原始 后缀）
- `scripts/init-project.sh` 新项目骨架顺手建 `docs/归档/{完成,旧版}/.gitkeep`
- 新增 `tests/test-docs-archive-convention.sh` 6 个 case（含 init-project e2e 验证）

**消费仓影响**：
- 新项目 init 即有 `docs/归档/` 骨架 + CLAUDE.md 含完整约定
- 老项目 sync 框架不会自动改业务 CLAUDE.md（业务实例）—— PM 可手工把约定段从 `templates/CLAUDE.md.tmpl` 复制到自己 CLAUDE.md，或参考 `templates/` 即可

**测试基线**：476 → 482（+6）

### 2026-05-26 — refactor(stages): Stage 1 中文名「感受问题」→「描述需求」

**问题**：「感受问题」措辞文艺、隐喻味重，PM 看 status-view banner / Stage 1→2 闸门时看不出这个 stage 实际要做什么（产出 brief.md 描述需求一句话）。

**改动**：单一真相源 `scripts/_lib/stages.py` STAGE_NAMES[1] 改成「描述需求」；下游 `status-view.py` / `req-transition.py` / `_lib/state.get_current_stage_banner` 输出自动跟着变。同步改 prose 引用 2 处：

- `skills/new-req/SKILL.md`：brief 原则段引号、二次确认门 banner 模板
- `skills/req-stage-gate/SKILL.md`：Stage 1 → 2 章节标题

**消费仓影响**：sync 后老 req（已过 Stage 1）的 banner / status-view 输出 stage 名跟着改；不影响数据 / 流程，纯文案。`docs/归档/` 历史快照保留旧名（不动）。

**测试基线**：476 / 0（无变化，未新增测试 —— 纯文案 rename + 单一真相源覆盖）。

### 2026-05-26 — fix(new-req): 加步骤 0「获取需求描述」严格规定无参数兜底文案

**问题**：PM 跑 `/pmai-new-req`（无参数），AI 临场编出工程黑话长文案：
> "你这次 /pmai-new-req 没带参数。请先告诉我这个新需求是什么（一句话即可，例如「实现用户登录」「租户内角色批量改名」），我才能生成 slug、确定编号、拉 worktree。"

PM 不需要知道 slug / 编号 / worktree 这些内部机制，"我才能..." 条件句式啰嗦。

**根因**：`skills/new-req/SKILL.md` 第一个步骤直接是「步骤 1：确定 req 编号」，**无显式步骤 0** 规定无参数时如何问 PM。AI 看 SKILL.md 直接跳步骤 1 想拉 worktree，发现没参数，自己临场编话术解释。

**改动**：
- SKILL.md 加「步骤 0：获取需求描述（无参数兜底）」
- 标准问法严格固定一句话：`请告诉我新需求是什么（一句话）。`
- 明示禁止扩展项：slug / 编号 / worktree 工程黑话 + "我才能..." 条件句式 + 多余举例
- 新增 `tests/test-new-req-no-arg-prompt.sh` 4 个 case 锁住文案

**测试基线**：472 → 476（+4），0 failure

### 2026-05-26 — fix(project-questioning): ROADMAP "历史 + 未来一张表" 引导（修 AI 漏写 done 行）

**问题**：PM 实测跑 /pmai-project-solution B 场景写 ROADMAP，AI 只写 planned 行，漏 7 个已 close 的 req 作 done 行。模板 HTML 注释虽写了三态 + "一个 req 走完后推进到 done"，但 §5.2 ROADMAP.md 写作规则只说"计划态 + planned"，AI 注意力集中在 §5.2 规则上，没读到模板注释，漏写历史。

**根因**：framework 引导分裂 —— 模板说一套（三态全 + 历史 + 未来），SKILL 写作规则只重复前向半段。AI 看 SKILL 规则按字面照做，不漏写才怪。

**改动**：
- `skills/_shared/project-questioning.md` §5.2 重写：
  - 明示 "ROADMAP 是「历史 + 未来一张表」，三态全用"
  - 三态表格（done / active / planned）注明何时写
  - 老项目首次跑 B 场景的具体写法：先扫 `requirements/closed/` 列已 close 全部 req-NNN 作 done 行，再问 PM planned 队列
  - 明示"漏写 done 行 = 体检不算齐"
- `skills/project-solution/SKILL.md` B 场景表格步骤 (3) 补"先扫 requirements/closed 写 done 行"指引
- `skills/_shared/project-questioning.md` §10.2 步骤总览 B 行同步加 closed 提示
- 新增 `tests/test-roadmap-guidance.sh` 5 个 case 锁引导文本完整性

**测试基线**：467 → 472（+5），0 failure

### 2026-05-26 — fix(status-view): 体检 hint 措辞 — 删误导项 + 不绑死 skill 内部场景

**问题**：体检 hint 旧措辞 `补法：发 /pmai-project-solution 季度规划场景；或新项目跑 /pmai-init-project 自动分发` 有 2 个问题 + 场景名"季度规划"本身狭窄：
- "或新项目跑 /pmai-init-project 自动分发"：体检在业务仓里跑，业务仓 PM 看到 `/pmai-init-project` 提示自然会试，撞上"必须在生成器仓"边界（实测 PM 跑了，被 AI 意图门挡住）
- 绑死场景名 + B 场景前置要求"`ROADMAP.md` 历史"：老项目首次补缺失文档没有历史，严格不满足。但 hint 强行绑场景
- "季度规划"狭窄：B 场景实际涵盖"季度 / 半年节奏"、"老项目首次补全 PROJECT 6 节 + ROADMAP"等，统一改名"产品路线规划"

**改动**：
- `scripts/status-view.py` 体检 hint 末行改为 `补法：发 /pmai-project-solution（skill 会按场景引导补全）`。最小信息原则：hint 只告诉 PM 调啥 skill，skill 内部走法留给 skill 自己引导
- 场景 B 改名 `季度规划` → `产品路线规划`（涵盖季度 / 半年节奏 + 老项目首次补全 ROADMAP）；触发条件 + 前置 + 步骤 1 同步扩展到支持"首次补无历史"
- 受影响文件：`skills/project-solution/SKILL.md` (3 处) + `skills/_shared/project-questioning.md` (4 处) + `skills/build-close-req/SKILL.md` (2 处) + `README.md` (1 处)
- 描述里指**时间维度**的"季度"保留（如"过去季度 roadmap 回顾"）；改的只是**场景名**

### 2026-05-26 — feat(status-view): 默认 + summary + narrative 都报项目体检（老项目升级后缺失文档全入口可见）

**问题**：PM 在消费仓问"当前项目情况"或走 session 起始播报（`status-view.py --narrative`）时，无 active req 状态只输出"目前没有 active req"。**完全不报缺什么产品级文档** —— 老项目升级框架后，新增的 `docs/PRODUCT-RULES.md` / `docs/ROADMAP.md` / 漏跑 migrate 残留的 `docs/CONTEXT.md` 都没人提，PM 永远不知道要补。

**根因（迭代两次）**：
- v1（首版）：`render_narrative` 加体检 —— 但 `task-status` skill 走的是 `python3 status-view.py`（默认分支），不走 `--narrative`，体检完全没人调
- v2（本版）：根因是体检不该绑死在某个 flag 上 —— **所有 PM-facing 的"问情况"入口**都应该看到。`框架同步-SOP.md` §4.10 的"读侧容错"被错误延伸到所有 PM 输出 —— 容错对，但播报应该 audit

**改动**：
- `scripts/status-view.py` 新增 `render_health_check(repo_root)`：检查 `docs/{PROJECT,PRODUCT-RULES,ROADMAP}.md` 存在性，缺则输出 1 段 hint（齐全则段不输出 → 新项目 0 噪音）
- 生成器仓自身（根有 `scripts/init-project.sh`）跳过体检，避免误报
- `docs/CONTEXT.md` 还在但无 `docs/PROJECT.md` → 额外提示"可能漏跑 migrate-context-to-project.py"
- main **三个 PM-facing 入口都调** `render_health_check`：
  - 默认输出（`task-status` skill 调用路径）
  - `--summary`
  - `--narrative`（session 起始播报）
- 不调的入口：`--banner-only`（嵌入式 stage banner，非"问情况"）+ `--timeline`（历史视图，非当前状态）
- 7 个新测试：`tests/test-narrative-mode.sh` T6-T12

**消费仓影响**：sync 后业务仓里 `status-view`（含 task-status skill 走的默认路径）/ `--summary` / `--narrative` 三个入口都自动报缺失。无 schema 迁移、无破坏改动；齐全的项目继续 0 噪音。

**测试**：467/0 PASS（460 + 7 新）

### 2026-05-26 — refactor: `roadmap.md` → `ROADMAP.md` 全量改名

**动机**：项目级文档命名层级对齐 —— `docs/PROJECT.md` / `docs/DESIGN.md` / `docs/PRODUCT-RULES.md` 都大写（稳定基线、project-level 文档），`docs/roadmap.md` 是同一档位但漏了大写。统一到大写减轻 PM 记忆负担。

**改动**：
- 模板 `git mv templates/roadmap.md.tmpl` → `templates/ROADMAP.md.tmpl`
- `scripts/init-project.sh` case 分支 `roadmap.md)` → `ROADMAP.md)`，落点 `docs/roadmap.md` → `docs/ROADMAP.md`
- 31 处 framework 引用全量改：`skills/{project-solution,init-project,codebase-audit}/SKILL.md` + `skills/_shared/{project-questioning,pm-view/askuser-rules}.md` + `templates/{CLAUDE,codebase-audit,ROADMAP}.md.tmpl`
- PM 文档同步改：`README.md` 阶段 C 说明 + `框架同步-SOP.md` §4.10 列表
- 历史快照保留小写：`docs/归档/完成/*.md` + `CHANGELOG.md` 已发布段（immutable，描述当时状态）

**消费仓影响**：
- 已有项目从未跑过 `/pmai-project-solution`（即没有 `docs/roadmap.md`）→ rsync 完即可，无业务迁移
- 已有 `docs/roadmap.md` 的消费仓 → 同步框架后须手工 `git mv docs/roadmap.md docs/ROADMAP.md`，并 grep 业务文档（CLAUDE.md / requirements/）里的 `roadmap.md` 引用一并改大写
- 不影响事件流 / 状态机，无 schema 迁移

### 2026-05-26 — fix(I-CT7): audit 诊断接上 `--repair-evidence` 合规救援路径

**问题**：`audit-task-events.py` I-CT7 挡下 close-task 时只输出「补齐缺失事件再重跑」，**完全没提** generator `bd1f1a3` 之后已建好的 `task-transition.py --repair-evidence` 合规救援命令。AI / PM 找不到合规出口 → 绕回 `task-events.py append --type execution_manual_completed` 裸补，没有 `repaired:true` 永久标记，事后审计无法区分救援 vs 伪造。

**根因**：救援路径建好但诊断引导没接上。memory `feedback_audit_block_not_infra_bug` 说"诚实记录 = `execution_manual_completed`"——指的是走 `--repair-evidence`，但 audit 输出从来不告诉调用方这件事。

**改动**：
- `scripts/audit-task-events.py` I-CT7 / I-CT8 失败诊断扩展为三路径：(1) 历史 task / 真实手动完成 → `--repair-evidence`（明示强制 reason + `repaired:true` 标记 + 警告不要裸 append + 命令找不到时引导走 §4.11 同步框架）；(2) 真实跳过状态机 → 回 `/pmai-task-execute`；(3) 整 req 放弃 → `/pmai-cancel-req`
- `框架同步-SOP.md` 新加 §4.11「消费仓 I-CT7 失败时的合规救援路径」—— 说明 `--repair-evidence` 在 `bd1f1a3` 之后才存在，消费仓没同步时的处理顺序（先同步 → 再救援 → 重跑 close-task），区分 case A（历史 task / 诚实救援）vs case B（PM 真实跳过 /pmai-task-execute，救援等于洗白偷工），给出框架同步阻塞时的临时绕过 payload 模板 + 技术债跟踪要求

**消费仓影响**：下次同步框架后，I-CT7 挡下来的提示从一句话变成完整 3 路径诊断；不需要 schema 迁移、不影响现有事件流。

### 2026-05-25 — fix: cleanup-pending-worktrees.sh L245 潜伏 unbound variable bug

**症状**：`tests/test-cleanup-pending.sh` C7 safety case fail —— 当存在 unsafe pending entry 时，脚本应 `exit 1` 并报警 "有未清理项保留..."，实际 exit 0 且警告残缺。

**根因**：L245 `echo "⚠️ 有未清理项保留在 $PENDING_FILE。请人工检查。"` —— `$PENDING_FILE` 紧跟中文句号 "。"（U+3002 UTF-8 三字节 e3 80 82），bash 在某些 locale 下 parse `$VAR` 时把后续 UTF-8 字节当变量名一部分，触发 `set -u` 抛 `PENDING_FILE�: unbound variable`；但因为该 `echo` 在 `if [ "$FAIL" -gt 0 ]` 分支内，错误吞掉后脚本 fall-through 到 fi 结束自然 exit 0（应该 exit 1）。

**潜伏时长**：bug 由 fcdf01e（2026-04-26）引入，但当时所有 test case 都走 happy path（FAIL=0 不进入此分支）；35cf17f（2026-05-25 harden workflow safety boundaries）加 C7 case 第一次造 FAIL>0 场景才暴露。

**修法**：`$PENDING_FILE` → `${PENDING_FILE}` 显式终结变量名边界。1 字符改动。

**测试基线**：`bash tests/run-all.sh` **455 / 0**（C7 修复 + 上条 task-status fix 2 个新 case 都过；不再有 pre-existing fail）。

---

### 2026-05-25 — fix: task 状态查询 vs v4.5 task md 单分支独占的 inconsistency

**问题**：v4.5 设计 task-confirm fork 后 `git rm` task md 从 req 分支（搬到 task 分支独家），但 `list_tasks()` 和 `/pmai-task-execute` 入口的 find 命令都只扫 req 分支视角，导致：

- **dangerous default**：`/pmai-task-status` 在 req 窗口扫不到已 fork 的 task → 错误推荐 `/pmai-build-close-req`；如果 PM 信了会**误关一个还有 task 待执行的 req**
- PM 在 req 窗口 `ls tasks/` 看不到 task md → AI 误判 "task 还没产" → 让 PM 重跑 `/pmai-task-spec` 浪费时间
- `/pmai-task-execute task-NNN`（短 ID）模式 find 扫不到 task-* worktree → 在已 confirm 的 task 上误报 "0 个匹配"

PM 在 example-consumer-app 真实跑出来证实了 `/pmai-task-status` 漏报 task-002，决定直接修而非起 D-v 设计 doc。

**修法**（example-consumer-app AI 给的 A 方案 ≈ 扫描机制扩展）：

- `scripts/_lib/state.py:list_tasks(req_dir, repo_root=None)`：加可选 repo_root 参数；传入时扫 `.worktrees/task-*/requirements/active/<req-id>/tasks/` 合并去重，同 task-id 优先 task 分支版（active 状态优于 req 分支 archived 状态）；不传 repo_root 保持旧行为（向后兼容）
- `scripts/_lib/state.py:get_overall_state()` 内部调用改传 repo_root（所有 status-view render_* 入口自动受益）
- `scripts/status-view.py` render_timeline 两处直接 list_tasks 调用补传 repo_root
- `skills/task-execute/SKILL.md` 入口步骤 1：短 ID + 无参两种模式的 find 命令扩到 `.worktrees/task-*/requirements/active`；加 v4.5 注释说明 fork 后 task md 在 task 分支独家
- `scripts/_lib/state_test.py:TestListTasks` 加 2 case：worktree_fallback_finds_task_branch_only_md / task_branch_md_preferred_over_req_branch

**业务仓需注意**：同步本修后 `/pmai-task-status` 在 req 窗口能正确看到已 fork 待执行的 task；可信任 status-view 给出的"下一步"建议（之前 PM 必须 `git worktree list` 手工核对）。

**测试基线**：`bash tests/run-all.sh` **454 pass / 1 fail**。fail 是 `test-cleanup-pending.sh` C7 safety case，**pre-existing**（stash 本次改动后跑仍 fail，与本次无关，另行追踪）。本次新增 2 case 全过（worktree_fallback_finds_task_branch_only_md / task_branch_md_preferred_over_req_branch）。

---

### 2026-05-25 — D-iv ship 后审计修复（漏改指针 + 死链 + 文档基线对齐）

新窗口连续大改后的隐性问题扫查（PM 主动发起），修以下 3 处：

- **askuser-rules 指针漏改**：vp-10 批量加指针时只覆盖 7 个核心 SKILL，遗漏 `skill-improve` + `task-submit`（两者都用 AskUserQuestion 走 PM 决策）。按 `_shared/pm-view/askuser-rules.md` §3.1 模板补齐 SKILL.md 顶部 blockquote。
- **死链 2 处**：
  - `RUNTIME.md` L18 写 `docs/设计/入口与全流程体验顺畅性.md` —— 实际已 `git mv` 到 `docs/归档/完成/`
  - `scripts/_lib/stages.py` L32 注释引 `docs/设计/Stage2-分析方式选择-office-hours.md` —— 实际归档为 `office-hours-跨stage1-2集成.md`
- **基线状态漂移**：`RUNTIME.md` L37 停留在 vp-12 commit 前的「期望 ~446，待跑」未完成态；实测 446/0 后改为「实测无回归」与 L129 / INDEX / CHANGELOG L105 对齐。

**业务仓需注意**：4 文件改动小范围，按 `框架同步-SOP.md` 跟随主仓 sync 即可。`skill-improve` + `task-submit` SKILL.md 同步后 PM 视觉上多 1 行 blockquote；功能上 agent 调 AskUser 严格按 §1 3 硬规则走。

**测试基线**：`bash tests/run-all.sh` **446/0**（实测无回归；4 文件改动均非测试覆盖路径）。

---

### 2026-05-25 — D-iv 入口与全流程体验顺畅性 ship 收尾（设计文档归档）

D-iv 批 1 + 批 2 全包技术 vp（vp-1 ~ vp-12，**vp-9 砍**）落地完毕：

- M1 init-project 一气呵成（vp-1 ~ vp-6）
- M2 banner + Decision gate label（vp-7 + vp-8）
- M4 AskUser 严格化（vp-10）
- M5 session 起始播报（vp-11）
- 批 2 文档同步（vp-12）

**收尾动作**：

- 设计文档 `docs/设计/入口与全流程体验顺畅性.md` 加「已落地状态」段（7 commits + 测试基线 446/0 + PM 验收清单）
- `git mv docs/设计/入口与全流程体验顺畅性.md → docs/归档/完成/入口与全流程体验顺畅性.md`
- `docs/INDEX.md` 设计/段砍 D-iv 行 + 归档/完成/段加 D-iv 行
- `RUNTIME.md`「当前位置」改为 D-iv ship + 下一步同步消费仓 + PM 自验收

**PM 验收清单**（同步消费仓后跑；不阻塞 ship）：

- [ ] PM 本仓外起测试项目跑 `/pmai-init-project` 端到端
- [ ] PM 跑 `bash scripts/measure-tthw.sh` 计时（期望 ≤ 30 分钟）
- [ ] PM 跑 `/pmai-project-solution` 4 场景对比一致性
- [ ] PM 同步到 ExampleConsumerApp 跑真实 req 验 banner / Decision gate / askuser / narrative
- [ ] 验收 finding 回头开 D-iv v0.3 patch vp（如有）

**业务仓需注意**：同步本 ship 时按 `框架同步-SOP.md` 走；vp-1 ~ vp-12 累计 14 个文件改动 + 4 个新文件，建议同步前 grep 现状对比预期差异。

---

### 2026-05-25 — D-iv M1 批 2（M2 + M4 + M5）vp-7~vp-12 全包落地

批 1（M1 init-project 一气呵成）ship 完后**接着 ship 批 2**（横切普推 banner / askuser / session 播报）。**M3 砍后（codex C-1）批 2 5 个 vp**：vp-7/vp-8 M2 + vp-10 M4 + vp-11 M5 + vp-12 文档同步。注：**不引入 `--auto` 或 chain flag**（M3 砍 + codex C-2）。

**vp-7：M2 banner-rules.md + status-view 复用**（T7）

- 新建 `skills/_shared/pm-view/banner-rules.md`（M2 + Decision gate label 单一真相源）：
  - §1 阶段 banner 格式（`━━━ PMAI ► <SKILL> ▸ Stage <N>/<T>: <Name> ━━━`；纯 ASCII 80 字符固定宽度）
  - §2 Next Up 块格式（`## ▶ Next Up — <command> <hint>`）
  - §3 Decision gate label 3 硬规则（M3 砍后整合 M2）：label=动作描述 / description=一句话 / 留守选项 Loop 回路 + 禁用模糊词 "OK"/"Proceed"/"Continue"
  - §4 实施指南 + 失败兜底
- 改 `scripts/_lib/state.py`：暴露 `get_current_stage_banner(req_dir, skill)` 函数（按 banner-rules.md §1.1 格式 + STAGE_NAMES 中文 stage 名）
- 改 `scripts/status-view.py`：加 `--banner-only` 模式 + `--skill` 参数 + `render_banner_only()` 函数（active req → banner / 无 active req → 占位 banner）

**vp-8：M2 banner + Decision gate label 全仓落地**（T8）

- 7 个核心 SKILL 顶部加 banner-rules 指针块（最小改动，不重写 SKILL.md 整体）：`init-project` / `new-req` / `req-stage-gate` / `task-confirm` / `task-execute` / `close-task` / `close-req`
- 新建 `tests/test-banner-label.sh`（5 cases）：
  - T1 7 个核心 SKILL 都引用 banner-rules.md
  - T2 banner-rules.md 含 §3 3 硬规则
  - T3 banner-rules.md 含禁用模糊词清单（OK / Proceed / Continue）
  - T4 `_lib/state.py` 暴露 `get_current_stage_banner`
  - T5 `status-view.py` 含 `--banner-only` 模式

**vp-10：M4 askuser-rules.md + 7 skill 加指针**（T9）

- 新建 `skills/_shared/pm-view/askuser-rules.md`（M4 单一真相源，gsd `#3018 failure mode` 照搬）：
  - §1 3 硬规则：① 空答/没答 → STOP wait next message 不重试不默认 ② 没拿到答案前禁止落盘 artifact ③ runtime 不支持时退化编号列表，仍 wait
  - §2 不在 scope：M4.1 / M4.2 / M4.3（禁逃生舱）
  - §3 实施指南（SKILL 顶部加引用 + 闸门类 AskUser 同时遵守 banner-rules §3）
- 7 个核心 SKILL 顶部加 askuser-rules 指针块（同 vp-8 7 个 SKILL）

**vp-11：M5 status-view --narrative + CLAUDE.md 章程**（T10）

- 改 `scripts/status-view.py`：加 `--narrative` 模式 + `render_narrative()` 函数
  - 范围降级（codex C-4）：当前 stage / 产物文件 / 最近 stage transition；**不到小节级**（不写「§四」/ commit hash 全文 / 「N 天前」相对时间）
  - 无 active req → 输出"目前没有 active req"，不编造（review R7 防幻觉）
- 改 `CLAUDE.md` 加章程章节「Session 起始播报」：
  - **PM 第一条 message 后**（codex C-3 校准描述：不是「PM 一开窗口」；LLM chat 模型固有限制）AI 必须先跑 `bash .claude/scripts/status-view.py --narrative` 输出播报，再回应 PM 请求
  - 生成器仓 vs 业务仓约束：本规则只在业务仓有 `.req-meta.json` 时生效
- 新建 `tests/test-narrative-mode.sh`（5 cases）：
  - T1 `--narrative` argparse 参数存在
  - T2 `render_narrative` 函数定义
  - T3 `render_banner_only` 函数定义（vp-7 同时验证）
  - T4 CLAUDE.md 含「Session 起始播报」章节 + 「PM 第一条 message 后」表述 + status-view.py --narrative 调用
  - T5 `render_narrative` 不含小节级 / commit hash / 「N 天前」字串（codex C-4 范围降级）

**vp-12：批 2 文档同步**（本条目；测试基线后置跑）

- `RUNTIME.md`「当前位置」批 2 落地（M3 砍批 2 5 vp 全完成）
- `CHANGELOG.md`「未发布」段加 vp-7~vp-12 条目（本条目）
- 跑 `tests/run-all.sh` 确认无回归

**业务仓需注意**：

- 同步后 7 个核心 SKILL 顶部多 2 行指针引用 `_shared/pm-view/banner-rules.md` + `askuser-rules.md`，PM 视觉上变化是 SKILL.md 前面多几行 markdown blockquote；功能上 agent 调 AskUserQuestion 严格按 askuser-rules.md §1 + Decision gate 按 banner-rules.md §3 走
- `status-view.py` 三个新模式：`--banner-only` / `--narrative` 不影响现有 list / summary / timeline 调用
- CLAUDE.md 加「Session 起始播报」章节：agent 在每个新 session 的 PM 第一条 message 后会先跑 narrative 播报；**不影响**当前 chat 内的后续 message

**M3 砍体现在批 2**：
- vp-9 整段砍（M3 闸门 Decision gate pattern 独立 vp → 合并到 vp-7/vp-8 M2 的 banner-rules.md §3）
- vp-12 描述**不含** `--auto` / chain flag / `auto_chain_active` 残留（codex C-2 文档自相矛盾修复完成）

**4 模块完整落地汇总**：M1（init-project 一气呵成）= vp-1 ~ vp-6 + M2（banner + Decision gate label）= vp-7 + vp-8 + M4（askuser 严格化）= vp-10 + M5（session 起始播报）= vp-11；批 2 文档同步 = vp-12；剩 vp-5b PM 手动验收 + vp-13 消费仓端到端 PM 手动跑（不可自动化）。

---

### 2026-05-25 — D-iv M1 vp-6：`/pmai-project-solution` 4 场景提问顺序细化

**vp-6 范围**（T6；review B1 + B 4 场景延伸）：vp-2 已经把 `/pmai-project-solution` SKILL.md 段 0 加了 4 场景判断**框架**（触发 / 输入态 / 提问顺序粗略描述）；vp-6 把提问顺序列**细化为具体的 5-7 步**，让实施时不需要每场景再想。

`skills/project-solution/SKILL.md`:

- frontmatter description 重写 4 场景描述（review B1 砍 E 后的 4 场景细化）：
  - A 项目方向重做（跑过几个 req 后发现产品定位偏了）
  - B 季度 / 半年规划（主动校准 PROJECT 6 节 + 重新排 roadmap）
  - C 老板 / 市场新方向（外部输入逼着改路线）
  - D brownfield 接入定方向（紧接 /pmai-codebase-audit 后跑）
- 段 0 场景判断表「提问顺序」列从粗略一句话改为**完整 5-7 步顺序**：
  - A 重做: 痛点诊断 → 定位 → 用户 → 路线 → 业务术语 → roadmap 重排
  - B 季度规划: 过去 roadmap 回顾 → 产品路线（新里程碑）→ roadmap → 业务术语增量（跳过定位 / 用户 / 技术栈）
  - C 新方向: 新方向 vs 现 PROJECT 差异 → 定位 → 用户 → 路线 → roadmap
  - D brownfield: 全文读 `docs/代码现状档.md` → 定位（codebase 反推 + PM 确认）→ 用户 → 路线 → 技术栈（codebase 抄）→ 业务术语 → roadmap
- 段 0 加通用约束（所有 4 场景都跑步骤 2 / 步骤 3 / 步骤 8 _shared 引用）

`skills/_shared/project-questioning.md`:

- §10.2 `vp-6 细化` placeholder 改为 `vp-6 已细化` + 加 4 场景顺序速查（指向 SKILL.md 段 0 完整表，避免双份维护）

**测试基线**：`bash tests/run-all.sh` **436/0**（无回归）。

**业务仓需注意**：

- `/pmai-project-solution` 4 场景全部走同一份 `_shared/project-questioning.md`（话术库 + 写作规则 + Decision gate 共享），但**提问顺序按场景定**（SKILL.md 段 0 表）
- D brownfield 场景必须先有 `docs/代码现状档.md`（`/pmai-codebase-audit` 产物），否则 step 0 失败
- A/B/C 场景前置须有 `docs/PROJECT.md`（greenfield 首次起项目要走 `/pmai-init-project` 一气呵成，不走 `/pmai-project-solution`）

**批 1（M1）至此 6 个 vp 全部完成**：vp-1（SKILL.md 4 阶段）+ vp-2（_shared 抽取）+ vp-3（阶段 D verify）+ vp-4（文档同步）+ vp-5a（自动化测试 +11 cases）+ vp-6（4 场景细化）；vp-5b PM 手动验收待 PM 自跑。

---

### 2026-05-25 — D-iv M1 vp-5a：3 个自动化测试套件落地（防回归）

**vp-5a 范围**（T5a；review T1 落实）：

- `tests/test-brownfield-detect.sh`（3 cases）：
  - T1 `init-project.sh` 已存在空目录 → 退出非 0 + stderr 含「目标目录已存在」
  - T2 `init-project.sh` 已存在含 `.git` 目录 → 同 T1（脚本不区分是否含 git，都拒）
  - T3 `init-project SKILL.md` 阶段 A 含 brownfield 描述 + `/pmai-codebase-audit` 引导 + 「两层都拦」接口约定（review C-7）
- `tests/test-no-duplicate-questioning.sh`（4 cases）：
  - T1 Decision gate 模板话术「我会开始写 .planning/PROJECT.md」只在 `_shared/project-questioning.md` 一处
  - T2 6 节齐不齐**完整调用代码块**（`PROJECT_STATE=$(python3 ...`）不出现在 `init-project` / `project-solution`（_shared + new-req legacy mini-fill 各持一份合法）
  - T3 `check-open-questions.py --require-section` 完整调用代码块只在 `_shared` 一处
  - T4 问题库典型话术「这个项目要解决什么核心问题」只在 `_shared` 一处
- `tests/test-shared-files-exist.sh`（4 cases）：
  - T1 `skills/_shared/project-questioning.md` 存在 + 含 §6 Decision gate + §5 写作规则
  - T2 `skills/_shared/PM-VIEW-RULES.md` 存在（7 个 skill 引用，防 R10）
  - T3 `skills/_shared/pm-view/` 目录存在 + 含 `.md` 子文件
  - T4 **前向链接完整性**：所有 SKILL.md 里 `@读 _shared/<path>.md` 引用 → 对应文件必须存在
- 3 个测试加进 `tests/run-all.sh`（test-init-project.sh 之后；test-tthw-smoke.sh 之前）

**测试基线**：`bash tests/run-all.sh` **425/0 → 436/0**（设计预期 +3，实际 +11；超出）。

**业务仓需注意**：

- 3 个新测试**仅检查框架自身一致性**（grep + assert 静态校验 + brownfield e2e），不依赖业务仓环境
- 未来改动 `_shared/project-questioning.md` 时，T4 引用完整性会自动验证（删了被引用的文件 → test fail）
- 改动 `init-project` / `project-solution` SKILL.md 时，T1/T2/T3 自动防止"反向把 _shared 内容复制回 SKILL.md"

---

### 2026-05-25 — D-iv M1 vp-3 + vp-4：阶段 D verify pass + 文档同步（README / RUNTIME / CHANGELOG）

**vp-3**（阶段 D 改"只汇总不 commit"）：vp-1 SKILL.md 已写对（"PROJECT.md / roadmap.md + commit 已在阶段 C 完成。阶段 D 只做终态输出"），verify pass，无单独 commit。

**vp-4**（文档同步，T4）：

- `README.md` § 快速开始 1：从 `bash scripts/init-project.sh ...` 直调 CLI 改为「PM 主动入口走 `/pmai-init-project` skill 一气呵成 4 阶段」（保留非交互 CLI 作 `measure-tthw` / smoke / 批量自动化的入口 invariant；review C-5）
- `README.md` § 完整 Skill 命令汇总：
  - `/pmai-init-project` 从「框架内部（PM 不直接用）」组**移到「启动新工作」组顶**（review B2）+ 加"(只在生成器仓里跑)"标记
  - `/pmai-project-solution` 描述更新为「项目方向规划：4 个独立场景（重做 / 季度规划 / 老板新方向 / brownfield 接入）」
  - 「框架内部」组留空（用 placeholder 行注明 `/pmai-init-project` 2026-05-25 后归入「启动新工作」）
- `RUNTIME.md`「当前位置」：D-iii v2 整段挪「历史阶段」，「当前位置」改写为 D-iv M1 vp-1/vp-2 落地 + vp-3 verify pass + 剩余 vp-4/5a/5b/6 清单
- `RUNTIME.md`「新窗口续接命令」：更新为 D-iv 进度（425/0 + vp 列表）
- `CHANGELOG.md`「未发布」段：本条目（vp-3 + vp-4 收尾）

**测试基线**：`bash tests/run-all.sh` **425/0**（无回归；文档改动不触动测试）。

---

### 2026-05-25 — D-iv M1 vp-2：`_shared/project-questioning.md` 抽取 + `/pmai-project-solution` 改 @读

**改造目标**：vp-1 让 `/pmai-init-project` 阶段 C 写为 `@读 _shared/project-questioning.md`，但该 `_shared` 文件还没创建（vp-1 commit 后 vp-2 commit 前手动跑 `/pmai-init-project` 阶段 C 会找不到 `_shared` 文件）。vp-2 创建该文件 + 把 `/pmai-project-solution` 现役 inline 提问法 / 写作规则改为 @读，让两个 skill 都引用同一份单一真相源。

**vp-2 范围**（M1 批 1 的第二个 vp；T2）：

- **新建** `skills/_shared/project-questioning.md`（253 行）：项目方向讨论的单一真相源
  - §1 调用方约定（init-project greenfield / project-solution 4 场景，调用方自己判断 + 自己排顺序）
  - §2 提问纪律（复用 `req-analysis` 提问法：分批 / 追问 / 收敛 / 编号作答）
  - §3 问题库（6 节 + 典型话术）
  - §4 未决问题闸门（暂存文件 `docs/.project-solution-open-questions.md` + `check-open-questions.py --require-section` + 禁逃生舱）
  - §5 写作规则（PROJECT.md 6 节模板 + roadmap.md 表头 + 产品路线节 vs roadmap 分工 + PM 视图规则）
  - §6 Decision gate 确认门（gsd Decision gate pattern 3 条硬规则 + AskUserQuestion 模板：「创建 PROJECT.md / 继续探索」+ Loop 回路）
  - §7 6 节齐不齐检查（`check-project-sections.py` + 禁逃生舱）
  - §8 PM 定稿展示模板
  - §9 atomic commit（gsd new-project Step 4 pattern：`docs: project direction settled`）
  - §10 调用方实现指南（§10.1 init-project greenfield / §10.2 project-solution 4 场景 vp-6 细化）
- **改** `skills/project-solution/SKILL.md`（238→158 行；瘦身 ~33%）：
  - frontmatter 更新（4 个独立调用场景 A/B/C/D；vp-6 后细化）
  - 加 § 段 0 场景判断（A 重做 / B 季度规划 / C 老板新方向 / D brownfield 接入）+ 提问顺序表（vp-6 细化）
  - 段 1 步骤 2/3 → @读 `_shared` §2/§3/§4
  - 段 2 步骤 4/5 → @读 `_shared` §5
  - 确认门步骤 7/8 → @读 `_shared` §6/§7/§8/§9
  - 步骤 6 精简 / 详细 / 混合模式选择保留（场景特定，不属 `_shared`）
  - Rules 加 ❌「重复 `_shared` 的提问法 / 5 组话术 / 写作规则」（必漂移）+ ✅ 段 0 场景判断
- **改** `skills/init-project/SKILL.md` 阶段 C 描述：把 inline Decision gate 选项副本改为「按 `_shared` §6.2，本 SKILL 不内嵌副本」（避免双份）

**单一真相源验证**：
- `Decision gate "创建 PROJECT.md / 继续探索"` 选项内容只在 `_shared/project-questioning.md:151-157` 一处定义；其他 SKILL 是说明性引用（不是 inline 副本）
- 6 节齐不齐检查 / 写作规则 / 提问纪律 / 问题库 / 未决问题闸门 全部只在 `_shared` 一处

**业务仓需注意**：
- `/pmai-project-solution` 行为不变（PM 视角依然走 4 段：场景判断 + 段 1 讨论 + 段 2 输出 + 确认门）；但内部走 @读 `_shared`，PM 不感知重构
- `/pmai-init-project` 阶段 C 现在可以跑（`_shared/project-questioning.md` 已存在）

**测试基线**：`bash tests/run-all.sh` **425/0**（无回归）。

---

### 2026-05-25 — D-iv M1 vp-1：`/pmai-init-project` skill 一气呵成 4 阶段重写（批 1 起手）

**改造目标**：`/pmai-init-project` 从"调 shell 脚本 + 提示 PM 下一步发 `/pmai-project-solution`"两步分裂入口，升级为 PM 主动一气呵成 4 阶段入口（参数 → 骨架 → 方向讨论 → Next Up）。

**vp-1 范围**（M1 批 1 的第一个 vp；T1）：

- 重写 `skills/init-project/SKILL.md`：
  - 顶部加 4 阶段 ASCII 流程图（review B3）
  - 阶段 A 明确 5 步参数顺序：项目名 → 落地路径 → **brownfield 检测闸门** → 一句话背景 → 项目意图（review A3）
  - **brownfield 接口约定**（review C-7）：skill 阶段 A 拒已存在目录 + 提示 `/pmai-codebase-audit`；脚本继续拒（两层都拦）
  - 阶段 B 用 Bash 调 `init-project.sh`（脚本作骨架构建器；non-interactive 入口 invariant 仍保留，review C-5）
  - 阶段 C @读 `_shared/project-questioning.md` 跑讨论（**vp-2 创建该 `_shared` 文件**）+ Decision gate 二选一 + atomic commit `docs: project direction settled`（review A5）
  - 阶段 D 只汇总不 commit（输出 Next Up 块格式）
  - 失败兜底速查（R10 init-project.sh 失败 / `_shared` 缺失；R11 PM 中途停清理）
- `scripts/init-project.sh`：
  - 删 `--help` 段末「成功后: cd <target-dir> / /pmai-new-req」echo + 加说明本脚本作 skill 阶段 B 调用 / 非交互 CLI 保留
  - 删脚本末尾 `下一步：cd $TARGET_DIR / 运行 /pmai-new-req` echo（入口语义已迁移到 `/pmai-init-project` skill）

**业务仓需注意**：
- 新建项目走 `/pmai-init-project` skill（**只在生成器仓里跑**，业务仓的 `/pmai-init-project` 不分发）—— skill 内嵌 4 阶段 agent 流程
- `init-project.sh` 仍是非交互参数化 CLI（`measure-tthw` / smoke / 批量自动化照旧调用，不受影响）
- vp-1 完成后 `_shared/project-questioning.md` 尚未创建 → vp-2 立刻接上；vp-1 commit 后 vp-2 commit 前 PM 不应该手动跑 `/pmai-init-project`（阶段 C 会找不到 `_shared` 文件）

**测试基线**：`bash tests/run-all.sh` **425/0**（无回归；`test-inject-structure.sh` "init-project SKILL 询问项目意图" case PASS 维持）。

---

### 2026-05-25 — D-iii v2：attachments AI 接管（helper-based，Model 2 — PM 不感知 attachments/ 目录）

**痛点**：PM 完全不知道现仓 attachments 机制（commit 65329d0 v0 落地）存在 —— 不知道路径 / 不知道如何上传 / 不知道后续 stage 能否读取。现有 trigger 1 / 2 都是 reactive（PM 主动提 / AI 写产出前扫），永远 silent 直到 PM "知道该说"，但 PM 没在任何 chat 看到过提示就永远学不到机制存在。根因 = **PM 视角 vs 工程视角错配**（与 D-i v4 "office-hours snapshot" 同款决策剧情）。

**方案**（设计 `docs/归档/完成/attachments-AI-接管.md` v2，落实 Codex outside voice Round 1 11 critical/high finding + Claude D1-D10 共 21 finding）：

1. **`scripts/_lib/attachments.py` 新建 helper-based 接管层**（与 D-i v4 `_lib.state.{get,set}_stage_source` 同款架构）：
   - `copy_attachment` / `register_attachment` / `list_attachments_seen` / `is_seen` / `remove_attachment` / `replace_attachment` 全套 API
   - **`SENSITIVE_PATH_PATTERNS` denylist**（12 个 pattern：`.env` / `.ssh/` / `.aws/` / `token` / `credential` 等）→ 命中 raise `SensitivePathError`
   - **`MAX_FILE_SIZE_MB = 50` hard cap** → 命中 raise `FileSizeError`，不依赖 pre-commit warn fail-open
   - Python `shutil.copy2` + `Path.expanduser()`（不靠 Bash cp）
2. **`.req-meta.json:attachments_seen` 字段约定** —— 状态真相源（与 D-i v4 `stage{N}_source` 同 meta）；引用 section 仅作 PM 可见展示
3. **`skills/_shared/pm-view/attachments-upload.md` 新建**单一真相源 prose（trigger 0 LLM 识别 + caller 调 helper + multi-batch / 替换 / 删除 / 冲突 / 失败兜底 + stage 前缀映射 + office-hours C4 边界）
4. **7 stage SKILL 加 trigger 0 inline 段**：new-req / req-analysis / prd-writing / task-spec / req-stage-gate / **implementation-design** / **task-plan**（最后两个 Codex C2 新增）
5. **`req-stage-gate` Stage 1→2 B 分支 trigger 0 disable**（C4 cross-design 冲突防护）：B 分支选 office-hours 源材料期间 PM 给的绝对路径走 `set_stage_source(tool='office-hours', origin=...)`（D-i v4 路径），**不**调 attachments helper
6. **`new-req` 步骤 4.5 commit pathspec 扩 `attachments/`**（C1 fix 破 I-DC1 dispatch 前 working tree 必须 clean 边界）
7. **`INVARIANTS.md` 立 I-RT10**（attachments_seen 字段 + helper-only + denylist + hard cap + B 分支 trigger 0 disable 边界）

**改动**（vp-1 → vp-7，~3.5h）：

- **vp-1**：`scripts/_lib/attachments.py` 新建（~370 行 Python：6 API + 2 异常 + 2 helper + denylist + hard cap）
- **vp-2**：`skills/_shared/pm-view/attachments-upload.md` 新建（~230 行 prose 单一真相源）
- **vp-3**：7 SKILL 加 trigger 0 段（new-req 完整段 + 6 SKILL 精简段 + 链 attachments-upload.md）
- **vp-3b**：`new-req/SKILL.md` 步骤 4.5 commit pathspec 加动态 attachments/ add（C1 fix）
- **vp-3c**：`req-stage-gate/SKILL.md` B 分支 trigger 0 disable prose（C4 fix）
- **vp-4**：`tests/test-attachments-helper.sh` 新增 **13 case**（unit + integration + regression + 静态 grep；含 trigger 2 regression for is_seen 改造）
- **vp-5**：`templates/req-prd.md.tmpl` 新加 `## 📎 参考材料`（保留 "九、附件（可选）" PRD 内置章节体系不动；两者并存语义清晰，比强行改名更对）
- **vp-6**：`skills/_shared/PM-VIEW-RULES.md` 加 §10 主索引行 + `INVARIANTS.md` 立 I-RT10
- **vp-7**：`CHANGELOG.md` 未发布段 + `RUNTIME.md`「当前位置」+ `docs/INDEX.md` + 设计文档归档 `git mv docs/设计/attachments-体验优化.md docs/归档/完成/attachments-AI-接管.md` + `docs/归档/完成/attachments-机制.md` 加 v2 升级指针段

**测试基线**：`bash tests/run-all.sh` **425 / 0**（前基线 412/0；D-iii v2 新增 13 case 全过 —— 设计预期 ≥ 423/0，**超出**）。

**v1 → v2 反转触发点**（同 D-i v4 Round 3 剧情）：

- Claude plan-eng-review D1-D10 共 10 finding 全 ACCEPT 后
- **Codex outside voice 11 critical/high finding** 集体指向根因 = v1 prose-only 应 helper 化（C1 Stage 1 dirty / C2 漏 Stage 5 入口 / C3 attachments_seen 没 helper 化 / C4 office-hours 冲突 / C5 stage 产出文档不存在 / C6 敏感文件 denylist / C7 Bash cp 脆 / C8 引用 section 不是真相源 / C9 模板事实 / C10 size fail-open / C11 测试不足）
- PM 拍 D12 = A：反转 v1 → v2 helper-based

**业务仓需注意**：

- **PM mental model 切 Model 2**：PM 完全不感知 `attachments/` 目录；想上传材料 → 在 chat 自然说 "我有 X 在路径 Y，重点 Z" → AI 后台搞定（与 D-i v4 office-hours snapshot 同款交互）
- **现有 trigger 1 / 2 保留作 fallback**：PM 真手动 cp 进 attachments/ 时 trigger 2 仍能识别（用 `is_seen` 判定基于 `attachments_seen` 真相源）
- **B 分支选 office-hours 源材料期间** trigger 0 禁用 —— PM 在 B 分支给绝对路径不会被误归档为 attachment
- **`/pmai-prd-writing` standalone 模式不启 trigger 0** —— standalone 不绑 req → 不入 req attachments/；想给独立 PRD 附件 PM 走手动 / 他路径
- **`.req-meta.json` 多 1 个字段**（`attachments_seen` 列表）；旧 req 无字段自动空列表 fallback，零迁移
- **hard cap 50MB**：超大文件 helper raise `FileSizeError`，chat 报错让 PM 走外部引用或拆小
- **敏感路径 denylist**：12 个 pattern（`.env` / `.ssh/` / `.aws/` / `token` / `credential` 等）→ PM 给 `~/.ssh/id_rsa` 类路径会被 helper 拒纳；消费仓发现新 case 扩 pattern

**待验项**（消费仓真实 req 验证）：

- **LLM 识别准确性**（同 D-i v4 R3-H2 DEFER）：trigger 0 LLM prose 判断 PM "上传意图" 准确性，相信 LLM + 消费仓真实 req 验证；如不行再独立 D-* 设计引入 LLM eval framework
- **`SENSITIVE_PATH_PATTERNS` 覆盖度**：经验值 12 pattern，可能漏 case（OAuth token cache / gcloud config 等）；消费仓使用后扩展
- **`MAX_FILE_SIZE_MB = 50` 是否合适**：经验值；可能要消费仓调整

### 2026-05-25 — D-i v4：office-hours 跨 Stage 1+2 集成 + Stage 2 真相源路径契约（snapshot 复制方案）

**痛点**：office-hours 在 Stage 1（`/pmai-new-req` 选项 1）+ Stage 2（讨论方式选择）两处都被调用看起来不合理 —— 用户视角是"一次需求讨论"，不该是 stage 1 + stage 2 两次拧巴。Stage 2 下游契约硬绑 `analysis.md` 也让"工具 2 选 1"（结构化批判 vs YC office-hours）走不通。

**方案**（设计 `docs/归档/完成/office-hours-跨stage1-2集成.md` v4，落实 Codex outside voice + 3 轮 plan-eng-review 全 21 决议）：

1. **PM 视角"一次需求讨论"体验包装**（`req-stage-gate` Stage 1→2）：brief 二次确认 + 讨论方式选择门合二为一，分流 A（`/pmai-req-analysis` 结构化批判）/ B（office-hours snapshot）
2. **Stage 2 真相源路径契约**（双分支）：A 分支产 `analysis.md` + 不变；B 分支 AI snapshot 复制 office-hours 设计稿到 `$ACTIVE_REQ_DIR/stage2-office-hours.md`（req 自包含，进 git / CI / 跨机器 / 归档 / consumer 仓全维度），不引用仓外 `~/.gstack/` 路径
3. **`.req-meta.json` 加 3 字段**：`stage{N}_source`（req 内相对路径）+ `stage{N}_tool`（产生工具名）+ `stage{N}_source_origin`（B 分支可选，外部源原始绝对路径追溯）
4. **helper**：`_lib.state.get_stage_source(req_dir, n)` + `set_stage_source(...)`，`STAGE_OUTPUT_FILES` 字典 schema 不动（保留 `dict[int, str]` 作 fallback）
5. **req-transition.py:247 改 helper**（R3-C1 必修，B 分支才推得进 Stage 3）
6. **下游 SKILL 通用化**（9 处）：prd-writing / implementation-design / task-spec / doc-update / close-task 文案 / templates/task-plan.md.tmpl / templates/CLAUDE.md.tmpl / input-flow.md / req-stage-gate Stage 2→3 段
7. **`/pmai-new-req` 砍选项 1**：单一 AI 引导路径；PM 想用 office-hours 风格深挖讨论 → Stage 2 stage-gate 入口 B 分支承接

**改动**（vp-1 → vp-7，~5h）：

- **vp-1**：`scripts/_lib/state.py` 加 `get_stage_source` + `set_stage_source` helper；`scripts/_lib/stages.py` 改注释扩双用途说明（transition 校验 + helper fallback）
- **vp-2** + **vp-3**：`skills/req-stage-gate/SKILL.md` Stage 1→2 重写为合二为一选择门 + 分流 A/B；B 分支含 office-hours bridge（探测 `~/.gstack/projects/$SLUG/*-design-*.md` 按 mtime + PM 三选一 + resume 协议 + AI snapshot 复制 + helper 写元数据 + term-detector hook + 推进确认门）
- **vp-2b**：`skills/new-req/SKILL.md` 砍选项 1（"自跑 /office-hours 整理 brief"），步骤 4 简化为 AI 引导 + PM 自写两路径；office-hours 边界注释移到 Stage 2
- **vp-4**：下游 9 处改 helper / 通用术语：`skills/{prd-writing,implementation-design,task-spec,doc-update,close-task,req-stage-gate}/SKILL.md` + `skills/_shared/pm-view/input-flow.md` + `templates/{task-plan.md.tmpl,CLAUDE.md.tmpl}`
- **vp-4b**：`scripts/req-transition.py:247` 由 `STAGE_OUTPUT_FILES[current]` 改 `get_stage_source(req_dir, current)`（R3-C1 必修）
- **vp-5**：`INVARIANTS.md` 立 I-RT9（stage N 真相源契约 + `stage{N}_source` / `stage{N}_tool` / `stage{N}_source_origin` 字段定义）
- **vp-6**：`tests/test-stage-source-helper.sh` 新增 11 case（get/set helper unit + grep 静态校验）+ `tests/test-req-transition.sh` 加 3 case（D-i v4 R3-C1 B 分支推进 / B 分支缺 snapshot 拒绝 / 旧 req fallback 兼容）
- **vp-7**：`CHANGELOG.md` 未发布段 + `docs/INDEX.md` + 设计文档归档为 `docs/归档/完成/office-hours-跨stage1-2集成.md`

**测试基线**：`bash tests/run-all.sh` **412/0**（前基线 398/0；D-i v4 新增 14 case 全过 —— 设计预期 ≥ 405/0，超出）。

**业务仓需注意**：

- **`/pmai-new-req` 选项 1 已砍**：旧版"自跑 /office-hours 整理 brief"路径不再可用；PM 想用 office-hours 风格请在 Stage 2 `req-stage-gate` 入口 B 分支跑（office-hours 设计稿会被 AI snapshot 复制进 req）
- **新 req `.req-meta.json` 多 3 字段**（`stage2_source` / `stage2_tool` / `stage2_source_origin`）；旧 req（无字段）自动 fallback `analysis.md`，零迁移
- **B 分支产物文件名固定**：`$ACTIVE_REQ_DIR/stage2-office-hours.md`；多次跑 B 分支会覆盖（PM 主动选 = 主动覆盖）。`stage2_source_origin` 字段失效不影响 req 自包含性
- **下游 SKILL prose 改通用术语"stage 2 真相源"**：A 分支 PM 体感不变（仍读 analysis.md）；B 分支 PM 看到 chat 里 AI 提到的是 stage 2 真相源 + stage2-office-hours.md
- **resume 协议**（PM 中断 chat 去跑 office-hours 后通知 AI 续 snapshot）：vp-2 实施时 stage-gate 状态机已落，PM 用任意句式回话 AI 都能接住（给文件名 / 给绝对路径 / 仅说"跑完了" → AI 自己重新探测）
- **R3-H2 DEFER**（office-hours prose 语义契约）：v4 §5.1 待验项 —— 相信 LLM 全文喂消化（v0 时 PM 已 ACCEPT prd-writing LLM-based fact），消费仓真实 req 验证 §六 派生质量；如不行再引入规范化 schema contract

### 2026-05-24 — 原型简化项登记机制 v2 落地（T1-T8 全包）

**痛点**：框架只有一份 req 级需求文档 `prd.md`，stage 3 是「评审用的完整真实需求」，close-req §2a 又把它「反向对齐成 as-built」。原型故意做得比 PRD 少的地方被 as-built 覆盖 —— 真实需求从评审文档消失。框架缺「原型故意简化」这个一等概念。

**方案**（设计 `docs/归档/完成/原型简化项-机制.md` v2，落实 plan-eng-review Round 1 全 16 决议）：`implementation-design.md` 加新段「段 1.5 · 原型简化项」（带稳定 `SIMP-ID`，stage 5 PM 确认门审定），按 PRD 锚点 join 下游消费链 task-spec / close-req / close-task。`adjustment` 事件 / `req-events.py` / close-req 现有覆盖逻辑完全不动。

**改动**（Lane A → Lane B/C，关键路径 worktree 并行 3.5-4h）：

- **T1**（templates/implementation-design.md.tmpl + skills/implementation-design/SKILL.md）：加段 1.5「原型简化项」（SIMP-ID schema + 表头 + 空态「无」）；SKILL.md 加 kind 1 登记引导（§2.1）+ Rules 定向豁免（段 1.5 允许写原型行为细节，scope delta 按定义不在 PRD）+ 扩 stage-5 确认门同时呈现架构决策表 + 段 1.5 摘要（D1）；自检从 4 段改 5 段
- **T2**（skills/task-spec/SKILL.md + templates/task.md.tmpl）：task-spec 步骤 6 加段 1.5 按 PRD 锚点 join 当前 task 逻辑（D5）—— 命中 → 实现规格 + PM 确认区·验收按简化后写 + 受影响验收项行内 `[SIMP-N]` 标签（D6）；task.md.tmpl §文档偏差区注释加 carve-out「已标记 SIMP-N 的不算偏差」（C3）
- **T3**（skills/build-close-req/SKILL.md §2a + close-report 模板）：§2a 改成两步顺序（D4）—— 先全部 adjustment overwrite → 再全部 simp 标注追加；锚点解析失败停下问 PM 不机械写错位（C5）；PRD 写回后跑 PM-view re-lint（D2 后置）；close-report 加「原型简化项」节（T8/C4）
- **T4**（skills/task-plan/SKILL.md §4.2 + templates/task-plan.md.tmpl）：§4.2 验收 GAP 清单加第三种处置「原型不实现（kind 2）→ 反向写回 implementation-design.md 段 1.5 SIMP-NN」（C1）；Required Inputs 补 `implementation-design.md`（C2）；task-plan.md.tmpl 修 stale `solution.md` 引用 → `prd.md + implementation-design.md`
- **T5**（scripts/check-doc-pm-view.py）：新增 `--simp-scope` 模式 —— implementation-design.md 段 1.5 scoped 校验（D2 源头约束），只校验段 1.5「真实需求」「原型本次计划简化为」「为什么简化」三个 PM 视图字段；其余段保持工程豁免不变；implementation-design SKILL.md 步骤 3.5 调用
- **T6**（skills/_shared/pm-view/input-flow.md）：Stage 5 task-plan 补 `implementation-design.md` 必读（C2）；Stage 6 task-spec 段 1.5 SIMP join 说明（C7）；§9.1.1 加「implementation-design.md 段 1.5 特殊读法」段（按 PRD 锚点 join，非 HOW-ID grep）
- **T7**（skills/build-close-task/SKILL.md Phase 1 步骤 1）：偏差分类「纠错 vs 计划外简化」（D3）—— 计划外简化停下问 PM 是否回填 implementation-design.md 段 1.5（C9 限定 close-time，已完成 task 不重生成）
- **T8**（scripts/derive-structure-templates.py → 派生 templates/工程结构约束-prototype.md）：「演示路径」深度指引补一句「本句覆盖路线默认范围 —— 不必为每个略过的 edge case 立 SIMP 行（C8 阈值：只登 PM 主动决策的决策级简化）」

**vp-5 解散（D7）**：测试折进各 T 自验，不堆独立测试 bucket。

**测试基线**：`bash tests/run-all.sh` **398/0**（无回归），新增 `--simp-scope` 正负向手动验证通过。

**业务仓需注意**：

- sync 后新跑 `/pmai-implementation-design` 自动产 5 段（含段 1.5）；旧 req 的 implementation-design.md 不强制回填，下次 revise 时按新模板。
- task-spec 现在按 PRD 锚点 join 段 1.5 SIMP 行 —— 业务仓 PRD §六章节命名应稳定（功能名级），否则 close-req §2a 锚点解析会失败 stop 问 PM。
- close-task Phase 1 现在多一步「偏差分类问 PM」 —— 计划外简化偏差才停，纠错偏差走原路径不打断（PM 体感同前）。
- 「原型本次实现」字段名已改「原型本次计划简化为」（C6 诚实命名）；段 1.5 模板与 SIMP 行参考 v2 设计文档 `docs/归档/完成/原型简化项-机制.md`。
- `task-plan.md.tmpl` 依赖从 `brief + analysis + solution.md` 改为 `brief + analysis + prd + implementation-design.md`；旧 task-plan 不强制回填。

### 2026-05-22 — 飞书发布兼容修复：§七 / §五 / §八 表格与列表格式

- `017b665` fix(prd-writing): §七 验收标准去引用块嵌复选框 + §5.1 多平台用户角色表 HTML→管道表格；publish-to-lark 加 HTML `<table>` 预检警告
- `6780f48` fix(prd-writing): §八 角色权限清单 / 原型列改造 + publish-to-lark 支持 `<!-- lark:no-merge -->` 标记

**背景**：飞书发布工具（lark-cli）只认 GFM 管道表格 / 标准 markdown，对若干结构会"悄悄塌掉"——发出来缺内容却不报错。prd-writing 原本多处要求用 HTML `<table>` 写带合并单元格的表，并断言"飞书识别 HTML 表格"——**该断言为假**。本次全面改造为管道表格：

1. **§七 验收标准**：`> - [ ]`（引用块嵌复选框列表）→ 普通项目符号（`**Story X**` 加粗 + `-`）。
2. **§五 5.1 用户角色（多平台 4 列表）**：HTML `<table>` → 管道表格 + 续行留空，跨行合并交给 publish-to-lark 的合并子系统。
3. **§八 角色权限清单**：HTML `<table>` → 管道表格。权限矩阵是「数据表」——空单元格 = 无权限（独立数据），与合并子系统「空 = 续行」语义冲突，因此整表不合并：「一级功能」列每行重复写全名，表前加 `<!-- lark:no-merge -->` 标记让 publish-to-lark 跳过该表合并。
4. **§六 原型列**：取消「原型」表格列。close-req 回填原型截图时作为独立图片放进 §6.X「原型」节，不塞进表格单元格（截图 + rowspan 的合并表无法干净发布）。

**新增 publish-to-lark 能力**：

- `<!-- lark:no-merge -->`：表前加此注释 → 该表跳过启发式合并、原样发布（按表格顺序与文档 table block 下标对齐；数量对不上则忽略全部标记并警告）。
- HTML `<table>` 预检：正文含裸 `<table>` → 打印警告 + 行号（不阻断发布）。

改动：`skills/prd-writing/SKILL.md`、`templates/req-prd.md.tmpl`、`skills/prd-writing/references/few-shots.md`、`skills/publish-to-lark/SKILL.md`、`scripts/publish-to-lark.py`。

**业务仓需注意**：

- sync 后新跑 prd-writing 生成的 §七 / §五 / §八 自动用新格式；已生成的 PRD 实例不强制回填，下次 rewrite 时收敛，或手动改后重发飞书。
- 权限矩阵类表（§八）发布前必须在表前保留 `<!-- lark:no-merge -->` 注释，否则空单元格会被错误合并。
- publish-to-lark 发布时若正文仍含 HTML `<table>`（旧 PRD）会打印警告 + 行号，提示改管道表格。

### 2026-05-22 — §8 后续收尾：DX 修复 + close-task 默认收尾 + modulespec 收敛 + CONTEXT→PROJECT 改名

- `6b2ce8c` refactor: docs/CONTEXT.md → docs/PROJECT.md 全量改名
- `57a6c4e` refactor(module-spec): 模板收敛 9→5 章 — 砍 req 级章节，活文档只留模块级内容
- `1e76be5` fix(dx): 统一入口脚本帮助/错误 — status-view 加示例段、init-project 缺参加命令骨架
- `f47f2fd` fix(dx): DX 诊断 4 修 — sed 元字符 / TTHW 工具误拷 / 正则过宽 / 中文 slug
- `bc979ce` fix(read_section): 标题正则容忍 emoji 前缀 — 修 v3 task close 被拦
- `07a3a09` feat(close-task): 验收通过后默认走收尾 — 逐条确认门改「默认走 / 必要才问」
- `07bf1c9` fix(init-project): skill 复制改递归 — 修 references/ 子目录漏拷

**⚠️ 一次性迁移（CONTEXT.md → PROJECT.md 改名）**：

框架把项目级文档 `docs/CONTEXT.md` 改名为 `docs/PROJECT.md`（与 GSD 命名层级对齐——GSD 的 `CONTEXT.md` 是 phase 级、`PROJECT.md` 才是项目级，原命名撞名错层）。已有消费仓 sync 后需跑一次 `scripts/migrate-context-to-project.py`：`git mv docs/CONTEXT.md docs/PROJECT.md` + 修业务文档（CLAUDE.md / docs/ / requirements/ 下 git-tracked 的 .md）里的 `CONTEXT.md` 引用，不碰 `.claude/`（框架同步资产已随同步更新）。幂等——已是 `PROJECT.md` 或新建仓跑本脚本是 no-op。详见 `框架同步-SOP.md` §4.10。

**业务仓需注意**：

- close-task：PM 验收通过后默认直接走完收尾（DESIGN / PRODUCT-RULES 提升、文档偏差对齐等），仅在「代码可能做错 / 需回退代码 / 范围变了」时才单独找 PM 确认；收尾末尾给汇总 + PM 总审 diff。
- modulespec 模板从 9 章收敛到 5 章：活文档只留模块级内容，req 级章节移除。已有消费仓的 modulespec 实例不强制回填，下次 close-req rewrite 时自然收敛。
- `init-project.sh` skill 复制改为递归（`cp -R`），修复 `references/` 子目录漏拷——此前 sync 出的消费仓 skill 可能缺 references/ 子文件，建议 sync 后抽查 `.claude/skills/*/references/`。
- read_section（`_lib/state.py`）标题正则现容忍 emoji 前缀——使用 emoji 标题的 v3 task 文件不再在 close 时被误拦。

### 2026-05-22 — GSD-review 管线重构全包

`31769a6` feat(gsd-review): §8 管线重构全包落地 — delta-2/3/4/7/8/9 + delta-1/5/6

**主线**：umbrella `docs/归档/完成/管线重构-GSD-review.md` §8 六步顺序全实施，替换旧 solution 双文件管线，接入 stage 3 PRD、req 级事件流、req 级实现设计、task 单文件 typed contract、跨功能产品规则和 brownfield codebase-audit。

**影响范围**：

- 新增 `scripts/req-events.py`：`decision` / `adjustment` 两类 req 级事件，落 `requirements/active/<reqid>/req-events.jsonl`。
- `req-solution` 退场，新增 `/pmai-project-solution`；`/pmai-prd-writing` 前移到 stage 3，产 req 级 `prd.md`。
- 新增 `/pmai-implementation-design` + `templates/implementation-design.md.tmpl`，stage 5 拆 task 前产 req 级 HOW。
- `task-spec` 从双文件改成单文件 typed contract（PM 确认区 / 执行区 / 审计区三区 + `task_format` 标记）。
- 新增 `templates/PRODUCT-RULES.md.tmpl`，升级 `DESIGN.md.tmpl`；close-task 支持 PRODUCT-RULES selective promote，req-stage-gate stage 4 每 req 必跑 gap-check。
- 新增 `/pmai-codebase-audit` brownfield 入口；close-req 步骤 2a 改为读 req-events adjustment，把 PRD 反向对齐为 as-built。
- 删除旧 solution / task engineering 双文件模板与 reconcile/hash 相关机制；`req-transition.py` 对在飞旧 req 保留文件存在性兼容（有 `solution.md` 且无 `prd.md` 时走旧 stage 3 判别）。

**业务仓需注意**：

- 同步后新 req 走 `analysis.md → prd.md → DESIGN/PRODUCT-RULES gap-check → implementation-design.md → task-plan.md → task 单文件 typed contract`。
- 在飞旧 req 可按文件存在性兼容继续跑完，但不建议新建旧 `solution.md`。
- 同步前后应按 `框架同步-SOP.md` 跑 Python import 冒烟和 `bash tests/run-all.sh`；当前生成器基线 395/0（`_lib.state_test` 57/0）。

### 2026-05-21 — accept 闸门 + evidence-repair

- `bd1f1a3` feat(task-transition): accept 闸门 + evidence-repair 命令
- `f37c83f` fix(task-transition): /review 跟进 — 接住 UnicodeDecodeError + repair-evidence 分支守卫

**修复**：

- `task-transition.py` 的「执行中→已完成」前移执行证据校验：事件流必须有 `execution_started` 或 `execution_manual_completed`，否则拒绝验收并提示先走 `/pmai-task-execute`。
- 新增受支持的 `--repair-evidence` 路径，用于 close-task 审计发现历史证据缺失但 PM 已确认真实完成时，受控补记带 `repaired` 标记的执行事件。
- 执行事件判定抽到 `scripts/_lib/events.py`，同时覆盖坏行 / 非法 UTF-8 / 分支已不存在等守卫。

**业务仓需注意**：

- 同步后不能再通过手改状态把未走执行通道的 task 直接验收为已完成。
- evidence repair 是审计修复口，不是常规工作流；必须保留理由和 PM 认定。

### 2026-05-21 — publish-to-lark 覆盖发布 frontmatter 泄漏修复

`bc9ab3f` fix(publish-to-lark): adapter 发送前剥离 frontmatter — 覆盖发布不再把 frontmatter 当正文

**缺陷**：`publish-to-lark` 把 markdown 开头的 YAML frontmatter（`---` 包裹的元数据块）当正文发给飞书——飞书不剥离 frontmatter，它会渲染成一段正文。覆盖发布结构上必然中招：首次发布回填的 `lark_doc_id` 就在 frontmatter 里，覆盖路径正是靠它触发的。

**修复**：frontmatter 拆分收口到 `scripts/_lib/lark_adapter.py` 的 `parse_frontmatter`（单一实现，`publish-to-lark.py` 改为 import 复用，删本地重复正则）；新增 `_markdown_body_path`，`docs_create_from_markdown` / `docs_update_from_markdown` 发送前统一剥掉 frontmatter 只发正文（与已有的 cwd workaround 同属「lark-cli markdown 发送怪癖」收口）。

**业务仓需注意**：

- 同步后 `publish-to-lark` 首次发布与覆盖发布都只发正文，本地 markdown 文件不改动。
- 此前已发布、顶部残留 frontmatter 段的飞书文档，重新跑一次发布即被覆盖修正。
- 影响文件：`scripts/_lib/lark_adapter.py` + `scripts/publish-to-lark.py` + `skills/publish-to-lark/SKILL.md`。

> （PM 完成 main 上的下一项改动后，先把 commit 加到这里；准备 sync 业务仓时再上提到「已发布版本」段，并在业务仓 sync commit 里引用本段。）

---

## 关联文档

- `RUNTIME.md` — 当前运行时状态 / 续接入口
- `框架同步-SOP.md` — 生成器 → 业务仓 hotfix 同步流程
- `INVARIANTS.md` — 框架不变量清单
- `docs/归档/完成/DX-AUDIT-2026-05-08.md` — 2026-05-08 DX 审计档案
