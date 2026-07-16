# Context reconstruction（PMAI 内部）

`context-pack` 是 design、build、自动收尾和文档更新共用的上下文编译步骤。它把现有真相源编译成一份带 hash 的内部 JSON，解决跨会话重复提问、历史决定漏读和旧证据继续沿用的问题。

## 调用

```bash
CONTEXT_PACK="$REPO_ROOT/.pm-workflow/context/<模块>.json"
python3 "$PMAI_HOME/scripts/context-pack.py" \
  --repo-root "$REPO_ROOT" \
  --module "docs/modules/<模块>" \
  --goal "<本轮目标>" \
  --output "$CONTEXT_PACK"
```

design 开场、build 开始、候选版本准备验收就绪快照、恢复中断工作、PM 定稿后的轻量 currentness 校验、merge 后文档更新前都重新编译。不得沿用更早会话里凭记忆整理的摘要。

## 读取顺序

1. `sources` 与 `input_hashes`：确认本轮读了哪些当前事实。
2. `decisions.active`：当前仍有效的决定；先主动浮现相关项，不再问 PM 已经拍过的问题。
3. `decisions.superseded` / `frozen`：只在判断为什么变化、是否要推翻旧方向时使用。
4. `question_like_rejected` / `unresolved_questions`：问句和讨论草稿不是决定，必须等 PM 明确回答。
5. `possible_conflicts`：同名 active 决定冲突时，回到 decision policy，让 PM 只拍真正的产品模型岔路。
6. `relevant_implementation_paths`：只作为读代码 / 原型的入口，不成为新的权威事实。

## 权威边界

- 模块当前规则：模块 `spec.md`。
- 模块为什么这样定：模块 `decisions.md`。
- 跨模块当前规则：`PRODUCT-RULES.md`。
- 项目级历史理路：`docs/decisions/` 冻结档。
- 当前产品事实：`PRODUCT-STATE.md`。
- 当前视觉基线：`DESIGN.md`。

context pack 只保存路径、摘要和 hash。发现内容冲突时回到上面的原文件处理；禁止直接编辑 context pack 把冲突“修好”。

## 新鲜度

- `source_hash` 变化：设计输入或相关真相源已变化，需要重新判断受影响的设计结论。
- `design_revision` 变化：build 期间 PM 接受了新的产品行为变化；旧验收证据立即失效。
- `implementation_commit` 变化：实现已经变，绑定旧 commit 的验收证据立即失效。

Skill 不得把“文件存在”当作“已经读过”；每次关键收敛点都运行编译器，并实际消费输出中的 active 决定、未决问题和 hash。
